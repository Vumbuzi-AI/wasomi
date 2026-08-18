defmodule Wasomi.Assessments.Workers.GenerateSmartTestWorkerTest do
  use Wasomi.DataCase

  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateSmartTestWorker
  alias Wasomi.Catalog

  setup :verify_on_exit!

  setup do
    module = course_module_fixture()
    lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_123")

    Catalog.upsert_lecture_transcript(lecture.id, %{
      status: :ready,
      text: "Video transcript text."
    })

    %{module: module, lecture: lecture}
  end

  defp args(smart_test), do: %{"smart_test_id" => smart_test.id}

  test "asks the generator for exactly the learner's mix and marks the test ready", %{
    lecture: lecture
  } do
    smart_test =
      smart_test_fixture(
        lecture: lecture,
        multiple_choice_count: 6,
        short_answer_count: 2,
        difficulty: 5
      )

    expect(Wasomi.SmartTestGeneratorMock, :generate_test, fn text, opts ->
      assert text =~ "Video transcript text."
      assert Keyword.get(opts, :multiple_choice_count) == 6
      assert Keyword.get(opts, :short_answer_count) == 2
      assert Keyword.get(opts, :difficulty) == 5

      {:ok, [draft_smart_test_choice_attrs(), draft_smart_test_written_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateSmartTestWorker, args(smart_test), [])

    updated = Assessments.get_smart_test!(smart_test.id)
    assert updated.status == :ready
    assert updated.questions_generated_count == 2

    assert [%{kind: :multiple_choice}, %{kind: :short_answer}] =
             Assessments.list_smart_test_questions(updated)
  end

  test "a module-scoped test draws on every lecture in the module", %{module: module} do
    smart_test = smart_test_fixture(module: module)

    expect(Wasomi.SmartTestGeneratorMock, :generate_test, fn text, _opts ->
      assert text =~ "Video transcript text."
      {:ok, [draft_smart_test_choice_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateSmartTestWorker, args(smart_test), [])
    assert Assessments.get_smart_test!(smart_test.id).status == :ready
  end

  test "no readable material leaves the test processing before the final attempt" do
    smart_test = smart_test_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GenerateSmartTestWorker, args(smart_test),
               attempt: 1,
               max_attempts: 5
             )

    assert Assessments.get_smart_test!(smart_test.id).status == :processing
  end

  test "no readable material marks the test failed on the last attempt" do
    smart_test = smart_test_fixture(module: course_module_fixture())

    assert {:error, :no_resources_available} =
             Oban.Testing.perform_job(GenerateSmartTestWorker, args(smart_test),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_smart_test!(smart_test.id)
    assert updated.status == :failed
    assert updated.error_message =~ "no_resources_available"
  end

  test "a generator error marks the test failed on the last attempt", %{lecture: lecture} do
    smart_test = smart_test_fixture(lecture: lecture)

    expect(Wasomi.SmartTestGeneratorMock, :generate_test, fn _text, _opts ->
      {:error, :rate_limited}
    end)

    assert {:error, :rate_limited} =
             Oban.Testing.perform_job(GenerateSmartTestWorker, args(smart_test),
               attempt: 5,
               max_attempts: 5
             )

    assert Assessments.get_smart_test!(smart_test.id).status == :failed
  end

  test "enqueue/1 is unique per test so double-clicking Create test can't double-generate", %{
    lecture: lecture
  } do
    smart_test = smart_test_fixture(lecture: lecture)

    assert {:ok, _job} = GenerateSmartTestWorker.enqueue(smart_test.id)
    assert {:ok, %{conflict?: true}} = GenerateSmartTestWorker.enqueue(smart_test.id)
  end
end
