defmodule Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker do
  @moduledoc """
  Extracts text from an admin-uploaded PDF and asks the configured
  `Wasomi.Assessments.QuestionGenerator` to draft multiple-choice questions
  from it, so a large document never blocks the admin's HTTP request.

  The generation record only flips to `:failed` on the job's last Oban
  attempt — earlier failures leave it `:processing` so the admin UI doesn't
  flicker to "failed" moments before a retry quietly succeeds.

  Every already-published lecture-quiz question from this module's lectures
  is fed to the generator as context to build on rather than re-derive (see
  `Wasomi.Assessments.list_lecture_quiz_question_prompts_for_module/1`), and
  any generated draft whose prompt exactly matches one of those verbatim is
  dropped before insertion — belt-and-suspenders on top of the prompt
  instruction, since the model isn't a hard guarantee against duplication.
  """

  use Oban.Worker,
    queue: :quiz_generation,
    max_attempts: 5

  alias Wasomi.Assessments

  @words_per_question_high_end 300
  @words_per_question_low_end 500
  @min_questions 3
  @max_questions 25

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"generation_id" => generation_id, "pdf_storage_key" => key}
      }) do
    generation = Assessments.get_generation!(generation_id)

    case run(generation, key) do
      :ok ->
        storage().delete(key)
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Assessments.mark_generation_failed(generation, inspect(reason))
          storage().delete(key)
        end

        {:error, reason}
    end
  end

  defp run(generation, key) do
    Assessments.mark_generation_processing(generation)
    quiz = Assessments.get_quiz!(generation.quiz_id)
    seed_prompts = Assessments.list_lecture_quiz_question_prompts_for_module(quiz.module_id)

    with {:ok, pdf_binary} <- storage().download(key),
         {:ok, text} <- pdf_extractor().extract_text(pdf_binary),
         {min_count, max_count} = question_count_range(text),
         {:ok, drafts} <-
           question_generator().generate_questions(text,
             min_count: min_count,
             max_count: max_count,
             avoid_duplicating: seed_prompts
           ),
         fresh_drafts = reject_duplicate_prompts(drafts, seed_prompts),
         {:ok, _count} <-
           Assessments.create_draft_questions_and_mark_ready(generation, fresh_drafts) do
      :ok
    end
  end

  defp reject_duplicate_prompts(drafts, seed_prompts) do
    seen = MapSet.new(seed_prompts, &normalize_prompt/1)
    Enum.reject(drafts, &MapSet.member?(seen, normalize_prompt(&1.prompt)))
  end

  defp normalize_prompt(prompt) when is_binary(prompt),
    do: prompt |> String.trim() |> String.downcase()

  defp normalize_prompt(_prompt), do: nil

  defp question_count_range(text) do
    word_count = text |> String.split(~r/\s+/, trim: true) |> length()

    min_count =
      word_count |> div(@words_per_question_low_end) |> max(@min_questions) |> min(@max_questions)

    max_count =
      word_count
      |> div(@words_per_question_high_end)
      |> max(min_count)
      |> min(@max_questions)

    {min_count, max_count}
  end

  defp storage,
    do: Application.get_env(:wasomi, :assessments_storage, Wasomi.Assessments.Storage.R2)

  defp pdf_extractor,
    do: Application.get_env(:wasomi, :pdf_extractor, Wasomi.Assessments.PdfExtractor.PdfToText)

  defp question_generator,
    do:
      Application.get_env(
        :wasomi,
        :question_generator,
        Wasomi.Assessments.QuestionGenerator.OpenAI
      )
end
