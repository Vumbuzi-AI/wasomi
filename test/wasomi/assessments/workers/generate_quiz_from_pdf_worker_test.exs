defmodule Wasomi.Assessments.Workers.GenerateQuizFromPDFWorkerTest do
  use Wasomi.DataCase

  import Wasomi.AssessmentsFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker

  setup :verify_on_exit!

  setup do
    %{generation: quiz_generation_fixture()}
  end

  defp args(generation, pdf_binary \\ "%PDF-1.4 fake") do
    %{"generation_id" => generation.id, "pdf_base64" => Base.encode64(pdf_binary)}
  end

  test "extracts text, generates drafts, and marks the generation ready", %{
    generation: generation
  } do
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
    long_text = Enum.map_join(1..20_000, " ", fn _ -> "word" end)

    expect(Wasomi.PdfExtractorMock, :extract_text, fn _binary -> {:ok, long_text} end)

    expect(Wasomi.QuestionGeneratorMock, :generate_questions, fn _text, opts ->
      assert Keyword.get(opts, :min_count) == 25
      assert Keyword.get(opts, :max_count) == 25
      {:ok, [draft_question_attrs()]}
    end)

    assert :ok = Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args(generation), [])
  end

  test "invalid base64 fails without calling the extractor or generator", %{
    generation: generation
  } do
    args = %{"generation_id" => generation.id, "pdf_base64" => "not-valid-base64!!"}

    assert {:error, :invalid_base64} =
             Oban.Testing.perform_job(GenerateQuizFromPDFWorker, args, [])
  end

  test "a PDF extraction failure leaves the generation processing before the final attempt", %{
    generation: generation
  } do
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
end
