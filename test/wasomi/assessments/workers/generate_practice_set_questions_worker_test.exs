defmodule Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorkerTest do
  use Wasomi.DataCase

  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorker
  alias Wasomi.Catalog

  setup :verify_on_exit!

  setup do
    module = course_module_fixture()
    lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_123")

    Catalog.upsert_lecture_transcript(lecture.id, %{
      status: :ready,
      text: "Video transcript text."
    })

    %{quiz: practice_set_fixture(module: module), module: module, lecture: lecture}
  end

  defp args(quiz), do: %{"practice_set_id" => quiz.id}

  test "gathers module text, generates questions, and marks the quiz ready", %{quiz: quiz} do
    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, _opts ->
      assert text =~ "Video transcript text."
      {:ok, [draft_question_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GeneratePracticeSetQuestionsWorker, args(quiz), [])

    updated = Assessments.get_practice_set!(quiz.id)
    assert updated.status == :ready
    assert updated.questions_generated_count == 1
    assert [%{prompt: _}] = Assessments.list_practice_set_questions(updated)
  end

  test "the question count range scales with document length", %{quiz: quiz, lecture: lecture} do
    long_text = Enum.map_join(1..20_000, " ", fn _ -> "word" end)
    Catalog.upsert_lecture_transcript(lecture.id, %{status: :ready, text: long_text})

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, opts ->
      assert Keyword.get(opts, :min_count) == 20
      assert Keyword.get(opts, :max_count) == 20
      {:ok, [draft_question_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GeneratePracticeSetQuestionsWorker, args(quiz), [])
  end

  test "no resources available leaves the quiz processing before the final attempt" do
    empty_quiz = practice_set_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GeneratePracticeSetQuestionsWorker, args(empty_quiz),
               attempt: 1,
               max_attempts: 5
             )

    updated = Assessments.get_practice_set!(empty_quiz.id)
    assert updated.status == :processing
  end

  test "no resources available marks the quiz failed on the last attempt" do
    empty_quiz = practice_set_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GeneratePracticeSetQuestionsWorker, args(empty_quiz),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_practice_set!(empty_quiz.id)
    assert updated.status == :failed
    assert updated.error_message =~ "no_resources_available"
  end

  test "an LLM failure is reported and retried the same way as a gathering failure", %{
    quiz: quiz
  } do
    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, _opts ->
      {:error, :refused}
    end)

    assert {:error, :refused} =
             Oban.Testing.perform_job(GeneratePracticeSetQuestionsWorker, args(quiz),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_practice_set!(quiz.id)
    assert updated.status == :failed
  end

  test "gathers text across every lecture in the module, video and document alike", %{
    module: module
  } do
    other_lecture = lecture_fixture(module_id: module.id, position: 2)

    resource =
      lecture_resource_fixture(
        lecture_id: other_lecture.id,
        kind: :document,
        storage_key: "lectures/notes.docx"
      )

    expect(Wasomi.LectureResourceReaderMock, :extract_text, fn res ->
      assert res.id == resource.id
      {:ok, "Document resource text."}
    end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, _opts ->
      assert text =~ "Video transcript text."
      assert text =~ "Document resource text."
      {:ok, [draft_question_attrs()]}
    end)

    quiz = practice_set_fixture(module: module)
    assert :ok = Oban.Testing.perform_job(GeneratePracticeSetQuestionsWorker, args(quiz), [])
  end

  test "a lecture-scoped quiz only gathers that one lecture's text", %{
    module: module,
    lecture: lecture
  } do
    other_lecture = lecture_fixture(module_id: module.id, position: 2)

    Catalog.upsert_lecture_transcript(other_lecture.id, %{
      status: :ready,
      text: "Other lecture's transcript."
    })

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, _opts ->
      assert text =~ "Video transcript text."
      refute text =~ "Other lecture's transcript."
      {:ok, [draft_question_attrs()]}
    end)

    lecture_quiz = practice_set_fixture(lecture: lecture)

    assert :ok =
             Oban.Testing.perform_job(GeneratePracticeSetQuestionsWorker, args(lecture_quiz), [])

    updated = Assessments.get_practice_set!(lecture_quiz.id)
    assert updated.status == :ready
    assert updated.lecture_id == lecture.id
  end
end
