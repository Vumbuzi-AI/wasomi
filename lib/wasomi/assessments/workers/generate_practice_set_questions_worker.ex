defmodule Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorker do
  @moduledoc """
  Gathers a module's document/transcript text and asks the configured
  `Wasomi.Assessments.QuestionGenerator` (the same adapter module-quiz
  generation uses — extra practice questions have the identical
  prompt/options shape, so no separate generator exists) to draft
  self-check questions from it. Mirrors
  `Wasomi.Assessments.Workers.GenerateFlashcardsWorker`, including only
  flipping the quiz to `:failed` on the job's last Oban attempt.
  """

  use Oban.Worker,
    queue: :quiz_generation,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:practice_set_id],
      states: :incomplete
    ]

  alias Wasomi.Assessments
  alias Wasomi.Assessments.ResourceText

  @words_per_question_high_end 300
  @words_per_question_low_end 500
  @min_questions 5
  @max_questions 20

  def enqueue(practice_set_id) do
    %{"practice_set_id" => practice_set_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"practice_set_id" => practice_set_id}
      }) do
    quiz = Assessments.get_practice_set!(practice_set_id)

    case run(quiz) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Assessments.mark_practice_set_failed(quiz, inspect(reason))
        end

        {:error, reason}
    end
  end

  defp run(quiz) do
    Assessments.mark_practice_set_processing(quiz)

    with {:ok, text} <- ResourceText.gather(scope(quiz)),
         {min_count, max_count} = question_count_range(text),
         {:ok, drafts} <-
           question_generator().generate_questions(text,
             min_count: min_count,
             max_count: max_count
           ),
         {:ok, _count} <- Assessments.mark_practice_set_ready(quiz, drafts) do
      :ok
    end
  end

  defp scope(%{module_id: module_id}) when not is_nil(module_id), do: {:module, module_id}
  defp scope(%{lecture_id: lecture_id}) when not is_nil(lecture_id), do: {:lecture, lecture_id}

  defp question_count_range(text) do
    word_count = text |> String.split(~r/\s+/, trim: true) |> length()

    min_count =
      word_count
      |> div(@words_per_question_low_end)
      |> max(@min_questions)
      |> min(@max_questions)

    max_count =
      word_count
      |> div(@words_per_question_high_end)
      |> max(min_count)
      |> min(@max_questions)

    {min_count, max_count}
  end

  defp question_generator,
    do:
      Application.get_env(
        :wasomi,
        :question_generator,
        Wasomi.Assessments.QuestionGenerator.OpenAI
      )
end
