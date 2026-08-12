defmodule Wasomi.Assessments.Workers.GenerateQuizFromPDFWorkerTest do
  use Wasomi.DataCase

  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker

  setup :verify_on_exit!

  setup do
    stub(Wasomi.AssessmentsStorageMock, :delete, fn _key -> :ok end)
    %{generation: quiz_generation_fixture()}
  end

  defp args(generation) do
    %{
      "generation_id" => generation.id,
      "pdf_storage_key" => "quiz-generations/#{generation.id}.pdf"
    }
  end

  defp stub_storage_download(pdf_binary \\ "%PDF-1.4 fake") do
    expect(Wasomi.AssessmentsStorageMock, :download, fn _key -> {:ok, pdf_binary} end)
  end

  test "extracts text, generates drafts, and marks the generation ready", %{
    generation: generation
  } do
    stub_storage_download()

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary ->
      {:ok, "Extracted training text."}
    end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, _opts ->
      assert text == "Extracted training text."
      {:ok, [draft_question_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])

    updated = Assessments.get_generation!(generation.id)
    assert updated.status == :ready
    assert updated.questions_generated_count == 1

    quiz = Assessments.get_quiz_with_questions!(generation.quiz_id)
    assert [%{status: :draft}] = quiz.questions
  end

  test "a short document still generates the minimum question range", %{
    generation: generation
  } do
    stub_storage_download()
    short_text = Enum.map_join(1..50, " ", fn _ -> "word" end)

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, short_text} end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, opts ->
      assert Keyword.get(opts, :min_count) == 3
      assert Keyword.get(opts, :max_count) == 3
      {:ok, [draft_question_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])
  end

  test "the question count range scales with document length", %{generation: generation} do
    stub_storage_download()
    text = Enum.map_join(1..2000, " ", fn _ -> "word" end)

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, text} end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, opts ->
      assert Keyword.get(opts, :min_count) == 4
      assert Keyword.get(opts, :max_count) == 6
      {:ok, [draft_question_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])
  end

  test "a very long document is capped at the maximum question count on both ends", %{
    generation: generation
  } do
    stub_storage_download()
    long_text = Enum.map_join(1..20_000, " ", fn _ -> "word" end)

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, long_text} end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, opts ->
      assert Keyword.get(opts, :min_count) == 25
      assert Keyword.get(opts, :max_count) == 25
      {:ok, [draft_question_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])
  end

  test "a storage download failure fails without calling the extractor or generator", %{
    generation: generation
  } do
    expect(Wasomi.AssessmentsStorageMock, :download, fn _key -> {:error, :not_found} end)

    assert {:error, :not_found} =
             Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])
  end

  test "a PDF extraction failure leaves the generation processing before the final attempt", %{
    generation: generation
  } do
    stub_storage_download()

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary ->
      {:error, :pdftotext_not_available}
    end)

    assert {:error, :pdftotext_not_available} =
             Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation),
               attempt: 1,
               max_attempts: 5
             )

    updated = Assessments.get_generation!(generation.id)
    assert updated.status == :processing
    refute updated.status == :failed
  end

  test "a PDF extraction failure marks the generation failed on the last attempt", %{
    generation: generation
  } do
    stub_storage_download()

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary ->
      {:error, :pdftotext_not_available}
    end)

    assert {:error, :pdftotext_not_available} =
             Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_generation!(generation.id)
    assert updated.status == :failed
    assert updated.error_message =~ "pdftotext_not_available"
  end

  test "an LLM failure is reported and retried the same way as an extraction failure", %{
    generation: generation
  } do
    stub_storage_download()

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, "some text"} end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, _opts ->
      {:error, :refused}
    end)

    assert {:error, :refused} =
             Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation),
               attempt: 5,
               max_attempts: 5
             )

    updated = Assessments.get_generation!(generation.id)
    assert updated.status == :failed
  end

  test "the generation succeeds, the stored PDF is deleted", %{generation: generation} do
    stub_storage_download()

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, "some text"} end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, _opts ->
      {:ok, [draft_question_attrs()]}
    end)

    key = "quiz-generations/#{generation.id}.pdf"
    expect(Wasomi.AssessmentsStorageMock, :delete, fn ^key -> :ok end)

    assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])
  end

  describe "seeding from this module's lecture quizzes" do
    test "passes existing lecture-quiz question prompts to the generator and drops exact-text duplicates from the result" do
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id)
      lecture_quiz = lecture_quiz_fixture(lecture: lecture)
      lecture_generation = lecture_quiz_generation_fixture(lecture_quiz: lecture_quiz)

      {:ok, 1} =
        Assessments.create_lecture_quiz_draft_questions_and_mark_ready(lecture_generation, [
          draft_question_attrs(%{prompt: "Existing lecture question?"})
        ])

      Assessments.publish_all_lecture_quiz_drafts(lecture_quiz)

      quiz = quiz_fixture(module: module)
      generation = quiz_generation_fixture(quiz: quiz)

      stub_storage_download()
      expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, "Training text."} end)

      expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, opts ->
        assert Keyword.get(opts, :avoid_duplicating) == ["Existing lecture question?"]

        {:ok,
         [
           draft_question_attrs(%{prompt: "Existing lecture question?"}),
           draft_question_attrs(%{prompt: "A brand new synthesis question?"})
         ]}
      end)

      assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])

      prompts =
        quiz.id
        |> Assessments.get_quiz_with_questions!()
        |> Map.fetch!(:questions)
        |> Enum.map(& &1.prompt)

      assert prompts == ["A brand new synthesis question?"]
    end

    test "seeds an empty list when the module has no lecture quizzes yet" do
      generation = quiz_generation_fixture()

      stub_storage_download()
      expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, "Training text."} end)

      expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, opts ->
        assert Keyword.get(opts, :avoid_duplicating) == []
        {:ok, [draft_question_attrs()]}
      end)

      assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])
    end

    test "generates module quiz from selected module resources (video transcript and document)" do
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_123")

      Wasomi.Catalog.upsert_lecture_transcript(lecture.id, %{
        status: :ready,
        text: "Video transcript text."
      })

      resource =
        lecture_resource_fixture(
          lecture_id: lecture.id,
          kind: :document,
          storage_key: "lectures/notes.docx"
        )

      quiz = quiz_fixture(module: module)
      generation = quiz_generation_fixture(quiz: quiz)

      expect(Wasomi.LectureResourceReaderMock, :extract_text, fn res ->
        assert res.id == resource.id
        {:ok, "Document resource text."}
      end)

      expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn text, _opts ->
        assert text =~ "Video transcript text."
        assert text =~ "Document resource text."
        {:ok, [draft_question_attrs(%{prompt: "Module synthesis question?"})]}
      end)

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["video:#{lecture.id}", "doc:#{resource.id}"]
      }

      assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])

      updated = Assessments.get_generation!(generation.id)
      assert updated.status == :ready
    end

    test "returns error for empty resource selection" do
      generation = quiz_generation_fixture()

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => []
      }

      assert {:error, :no_resources_selected} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "returns error for an invalid resource key" do
      generation = quiz_generation_fixture()

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["bogus_key"]
      }

      assert {:error, :invalid_resource_key} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "returns error for a malformed video key" do
      generation = quiz_generation_fixture()

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["video:abc"]
      }

      assert {:error, :invalid_resource_key} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "returns error for a malformed doc key" do
      generation = quiz_generation_fixture()

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["doc:not_a_number"]
      }

      assert {:error, :invalid_resource_key} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "returns error when video transcript is not ready" do
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_456")

      Wasomi.Catalog.upsert_lecture_transcript(lecture.id, %{
        status: :processing,
        text: nil
      })

      quiz = quiz_fixture(module: module)
      generation = quiz_generation_fixture(quiz: quiz)

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["video:#{lecture.id}"]
      }

      assert {:error, {:transcript_not_ready, :processing}} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "returns error when video has no transcript at all" do
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_789")
      quiz = quiz_fixture(module: module)
      generation = quiz_generation_fixture(quiz: quiz)

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["video:#{lecture.id}"]
      }

      assert {:error, :transcript_not_ready} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "returns error when document resource does not exist" do
      generation = quiz_generation_fixture()

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["doc:999999"]
      }

      assert {:error, :resource_not_found} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "returns error when resource is not a document" do
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id)

      resource =
        lecture_resource_fixture(
          lecture_id: lecture.id,
          kind: :video,
          storage_key: "lectures/clip.mp4"
        )

      quiz = quiz_fixture(module: module)
      generation = quiz_generation_fixture(quiz: quiz)

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["doc:#{resource.id}"]
      }

      assert {:error, {:unsupported_resource_kind, :video}} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end

    test "halts on first failing resource in a mixed selection" do
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id, video_asset_id: "asset_halt")
      quiz = quiz_fixture(module: module)
      generation = quiz_generation_fixture(quiz: quiz)

      args = %{
        "generation_id" => generation.id,
        "resource_selection" => ["video:#{lecture.id}", "doc:999999"]
      }

      assert {:error, :transcript_not_ready} =
               Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
    end
  end
end
