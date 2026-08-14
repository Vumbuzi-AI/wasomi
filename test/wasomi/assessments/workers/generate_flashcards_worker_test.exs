defmodule Wasomi.Assessments.Workers.GenerateFlashcardsWorkerTest do
  use Wasomi.DataCase

  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateFlashcardsWorker
  alias Wasomi.Catalog

  setup :verify_on_exit!

  setup do
    module = course_module_fixture()
    lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_123")

    Catalog.upsert_lecture_transcript(lecture.id, %{
      status: :ready,
      text: "Video transcript text."
    })

    %{set: flashcard_set_fixture(module: module), module: module, lecture: lecture}
  end

  defp args(set), do: %{"flashcard_set_id" => set.id}

  test "gathers module text, generates cards, and marks the set ready", %{set: set} do
    expect(Wasomi.FlashcardGeneratorMock, :generate_flashcards, fn text, _opts ->
      assert text =~ "Video transcript text."
      {:ok, [draft_flashcard_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateFlashcardsWorker, args(set), [])

    updated = Assessments.get_flashcard_set!(set.id)
    assert updated.status == :ready
    assert updated.cards_generated_count == 1
    assert [%{front: _, back: _}] = Assessments.list_flashcards(updated)
  end

  test "the card count range scales with document length", %{set: set, lecture: lecture} do
    long_text = Enum.map_join(1..20_000, " ", fn _ -> "word" end)
    Catalog.upsert_lecture_transcript(lecture.id, %{status: :ready, text: long_text})

    expect(Wasomi.FlashcardGeneratorMock, :generate_flashcards, fn _text, opts ->
      assert Keyword.get(opts, :min_count) == 40
      assert Keyword.get(opts, :max_count) == 40
      {:ok, [draft_flashcard_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateFlashcardsWorker, args(set), [])
  end

  test "no resources available leaves the set processing before the final attempt" do
    empty_set = flashcard_set_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GenerateFlashcardsWorker, args(empty_set),
               attempt: 1,
               max_attempts: 5
             )

    updated = Assessments.get_flashcard_set!(empty_set.id)
    assert updated.status == :processing
  end

  test "no resources available marks the set failed on the last attempt" do
    empty_set = flashcard_set_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GenerateFlashcardsWorker, args(empty_set),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_flashcard_set!(empty_set.id)
    assert updated.status == :failed
    assert updated.error_message =~ "no_resources_available"
  end

  test "an LLM failure is reported and retried the same way as a gathering failure", %{
    set: set
  } do
    expect(Wasomi.FlashcardGeneratorMock, :generate_flashcards, fn _text, _opts ->
      {:error, :refused}
    end)

    assert {:error, :refused} =
             Oban.Testing.perform_job(GenerateFlashcardsWorker, args(set),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_flashcard_set!(set.id)
    assert updated.status == :failed
  end

  test "gathers text across every lecture in the module, video and document alike", %{
    module: module
  } do
    other_lecture = lecture_fixture(module_id: module.id, position: 2)

    lecture_resource_fixture(
      lecture_id: other_lecture.id,
      kind: :document,
      storage_key: "lectures/notes.docx"
    )
    |> then(fn resource ->
      expect(Wasomi.LectureResourceReaderMock, :extract_text, fn res ->
        assert res.id == resource.id
        {:ok, "Document resource text."}
      end)
    end)

    expect(Wasomi.FlashcardGeneratorMock, :generate_flashcards, fn text, _opts ->
      assert text =~ "Video transcript text."
      assert text =~ "Document resource text."
      {:ok, [draft_flashcard_attrs()]}
    end)

    set = flashcard_set_fixture(module: module)
    assert :ok = Oban.Testing.perform_job(GenerateFlashcardsWorker, args(set), [])
  end

  test "a lecture-scoped set only gathers that one lecture's text", %{
    module: module,
    lecture: lecture
  } do
    other_lecture = lecture_fixture(module_id: module.id, position: 2)

    Catalog.upsert_lecture_transcript(other_lecture.id, %{
      status: :ready,
      text: "Other lecture's transcript."
    })

    expect(Wasomi.FlashcardGeneratorMock, :generate_flashcards, fn text, _opts ->
      assert text =~ "Video transcript text."
      refute text =~ "Other lecture's transcript."
      {:ok, [draft_flashcard_attrs()]}
    end)

    lecture_set = flashcard_set_fixture(lecture: lecture)
    assert :ok = Oban.Testing.perform_job(GenerateFlashcardsWorker, args(lecture_set), [])

    updated = Assessments.get_flashcard_set!(lecture_set.id)
    assert updated.status == :ready
    assert updated.lecture_id == lecture.id
  end
end
