defmodule Wasomi.Assessments.Workers.GenerateStudyGuideWorkerTest do
  use Wasomi.DataCase

  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateStudyGuideWorker
  alias Wasomi.Catalog

  setup :verify_on_exit!

  setup do
    module = course_module_fixture(title: "Barcode basics")
    lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_123")

    Catalog.upsert_lecture_transcript(lecture.id, %{
      status: :ready,
      text: "Video transcript text."
    })

    %{module: module, lecture: lecture}
  end

  defp args(study_guide), do: %{"study_guide_id" => study_guide.id}

  test "passes the learner's whole brief to the generator and writes the document", %{
    lecture: lecture
  } do
    study_guide =
      study_guide_fixture(
        lecture: lecture,
        style: :story,
        depth: :deep,
        reading_level: :beginner,
        include_examples: false,
        include_key_terms: true,
        focus: "focus on check digits"
      )

    expect(Wasomi.StudyGuideGeneratorMock, :generate_guide, fn text, opts ->
      assert text =~ "Video transcript text."
      assert Keyword.get(opts, :style) == :story
      assert Keyword.get(opts, :depth) == :deep
      assert Keyword.get(opts, :reading_level) == :beginner
      assert Keyword.get(opts, :include_examples) == false
      assert Keyword.get(opts, :include_key_terms) == true
      assert Keyword.get(opts, :focus) == "focus on check digits"
      assert Keyword.get(opts, :scope_label) == lecture.title

      {:ok, draft_study_guide_attrs()}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateStudyGuideWorker, args(study_guide), [])

    updated =
      study_guide.id
      |> Assessments.get_study_guide!()
      |> Assessments.load_study_guide_sections()

    assert updated.status == :ready
    assert updated.sections_generated_count == 2
    assert updated.title == "How GS1 barcodes identify a product"
    assert [first, second] = updated.study_guide_sections
    assert first.position == 1
    assert first.heading == "Where the number comes from"
    assert first.bullets == ["The prefix is issued by GS1", "The item number is assigned by you"]
    assert first.callout == "You never invent your own prefix."
    assert second.position == 2
    assert [%{term: "GTIN"}] = updated.key_terms
    assert updated.key_takeaways != []
  end

  test "a module-scoped guide draws on every lecture in the module and is titled for it", %{
    module: module
  } do
    study_guide = study_guide_fixture(module: module)

    expect(Wasomi.StudyGuideGeneratorMock, :generate_guide, fn text, opts ->
      assert text =~ "Video transcript text."
      assert Keyword.get(opts, :scope_label) == "Barcode basics"
      {:ok, draft_study_guide_attrs()}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateStudyGuideWorker, args(study_guide), [])
    assert Assessments.get_study_guide!(study_guide.id).status == :ready
  end

  test "no readable material leaves the guide processing before the final attempt" do
    study_guide = study_guide_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GenerateStudyGuideWorker, args(study_guide),
               attempt: 1,
               max_attempts: 5
             )

    assert Assessments.get_study_guide!(study_guide.id).status == :processing
  end

  test "no readable material marks the guide failed on the last attempt" do
    study_guide = study_guide_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GenerateStudyGuideWorker, args(study_guide),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_study_guide!(study_guide.id)
    assert updated.status == :failed
    assert updated.error_message =~ "no_resources_available"
  end

  test "a generator error marks the guide failed on the last attempt", %{lecture: lecture} do
    study_guide = study_guide_fixture(lecture: lecture)

    expect(Wasomi.StudyGuideGeneratorMock, :generate_guide, fn _text, _opts ->
      {:error, :rate_limited}
    end)

    assert {:error, :rate_limited} =
             Oban.Testing.perform_job(GenerateStudyGuideWorker, args(study_guide),
               attempt: 5,
               max_attempts: 5
             )

    assert Assessments.get_study_guide!(study_guide.id).status == :failed
  end

  test "a guide with no usable section fails rather than landing empty", %{lecture: lecture} do
    study_guide = study_guide_fixture(lecture: lecture)

    expect(Wasomi.StudyGuideGeneratorMock, :generate_guide, fn _text, _opts ->
      {:ok, draft_study_guide_attrs(sections: [])}
    end)

    assert {:error, :no_valid_sections_generated} =
             Oban.Testing.perform_job(GenerateStudyGuideWorker, args(study_guide),
               attempt: 5,
               max_attempts: 5
             )

    assert Assessments.get_study_guide!(study_guide.id).status == :failed
  end

  test "enqueue/1 is unique per guide so double-clicking can't double-generate", %{
    lecture: lecture
  } do
    study_guide = study_guide_fixture(lecture: lecture)

    assert {:ok, _job} = GenerateStudyGuideWorker.enqueue(study_guide.id)
    assert {:ok, %{conflict?: true}} = GenerateStudyGuideWorker.enqueue(study_guide.id)
  end
end
