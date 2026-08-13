defmodule Wasomi.Assessments.Workers.GenerateLectureQuizWorkerTest do
  use Wasomi.DataCase

  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateLectureQuizWorker
  alias Wasomi.Catalog

  setup :verify_on_exit!

  defp args(generation), do: %{"generation_id" => generation.id}

  describe "generating from the primary video's transcript" do
    setup do
      lecture = lecture_fixture()
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :ready, text: "Lecture content."})
      quiz = lecture_quiz_fixture(lecture: lecture)

      %{
        lecture: lecture,
        generation:
          lecture_quiz_generation_fixture(
            lecture_quiz: quiz,
            resource_selection: ["video"],
            question_count_requested: 5,
            difficulty: :hard
          )
      }
    end

    test "drafts questions from the transcript and marks the generation ready", %{
      generation: generation
    } do
      expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, opts ->
        assert text == "Lecture content."
        assert Keyword.get(opts, :min_count) == 5
        assert Keyword.get(opts, :max_count) == 5
        assert Keyword.get(opts, :difficulty) == :hard
        {:ok, [draft_question_attrs()]}
      end)

      assert :ok = Oban.Testing.perform_job(GenerateLectureQuizWorker, args(generation), [])

      updated = Assessments.get_lecture_quiz_generation!(generation.id)
      assert updated.status == :ready
      assert updated.questions_generated_count == 1

      quiz = Assessments.get_lecture_quiz_with_questions!(generation.lecture_quiz_id)
      assert [%{status: :draft}] = quiz.questions
    end

    test "a not-yet-ready transcript fails without calling the generator", %{
      lecture: lecture,
      generation: generation
    } do
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :processing})

      assert {:error, {:transcript_not_ready, :processing}} =
               Oban.Testing.perform_job(GenerateLectureQuizWorker, args(generation), [])
    end

    test "leaves the generation processing before the final attempt on failure", %{
      lecture: lecture,
      generation: generation
    } do
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :failed})

      assert {:error, {:transcript_not_ready, :failed}} =
               Oban.Testing.perform_job(GenerateLectureQuizWorker, args(generation),
                 attempt: 1,
                 max_attempts: 5
               )

      updated = Assessments.get_lecture_quiz_generation!(generation.id)
      assert updated.status == :processing
    end

    test "marks the generation failed on the last attempt", %{
      lecture: lecture,
      generation: generation
    } do
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :failed})

      assert {:error, {:transcript_not_ready, :failed}} =
               Oban.Testing.perform_job(GenerateLectureQuizWorker, args(generation),
                 attempt: 5,
                 max_attempts: 5
               )

      updated = Assessments.get_lecture_quiz_generation!(generation.id)
      assert updated.status == :failed
      assert updated.error_message =~ "transcript_not_ready"
    end
  end

  describe "generating from a document resource" do
    test "reads the resource via the configured reader and drafts questions from it" do
      lecture = lecture_fixture()

      resource =
        lecture_resource_fixture(
          lecture_id: lecture.id,
          kind: :document,
          storage_key: "lectures/slides.pdf"
        )

      quiz = lecture_quiz_fixture(lecture: lecture)

      generation =
        lecture_quiz_generation_fixture(
          lecture_quiz: quiz,
          resource_selection: [to_string(resource.id)],
          question_count_requested: 8
        )

      expect(Wasomi.LectureResourceReaderMock, :extract_text, fn res ->
        assert res.id == resource.id
        {:ok, "Slide deck text."}
      end)

      expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, _opts ->
        assert text == "Slide deck text."
        {:ok, [draft_question_attrs()]}
      end)

      assert :ok = Oban.Testing.perform_job(GenerateLectureQuizWorker, args(generation), [])

      updated = Assessments.get_lecture_quiz_generation!(generation.id)
      assert updated.status == :ready
    end
  end

  describe "generating from multiple resources at once" do
    test "concatenates every selected source's text before generating" do
      lecture = lecture_fixture()
      Catalog.upsert_lecture_transcript(lecture.id, %{status: :ready, text: "Video text."})

      resource =
        lecture_resource_fixture(
          lecture_id: lecture.id,
          kind: :document,
          storage_key: "lectures/slides.pdf"
        )

      quiz = lecture_quiz_fixture(lecture: lecture)

      generation =
        lecture_quiz_generation_fixture(
          lecture_quiz: quiz,
          resource_selection: ["video", to_string(resource.id)]
        )

      expect(Wasomi.LectureResourceReaderMock, :extract_text, fn _res -> {:ok, "Slide text."} end)

      expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, _opts ->
        assert text =~ "Video text."
        assert text =~ "Slide text."
        {:ok, [draft_question_attrs()]}
      end)

      assert :ok = Oban.Testing.perform_job(GenerateLectureQuizWorker, args(generation), [])
    end
  end
end
