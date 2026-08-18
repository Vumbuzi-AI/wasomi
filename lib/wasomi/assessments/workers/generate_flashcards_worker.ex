defmodule Wasomi.Assessments.Workers.GenerateFlashcardsWorker do
  @moduledoc """
  Drafts a module's (or lecture's) flashcards ahead of the learner opening
  the Flashcards section, so that first visit never blocks on generation.

  Cards are always drawn from the scope's document/transcript text.

  Mirrors `Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker`'s
  resource-driven path, including only flipping the set to `:failed` on the
  job's last Oban attempt.
  """

  use Oban.Worker,
    queue: :quiz_generation,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:flashcard_set_id],
      states: :incomplete
    ]

  alias Wasomi.Assessments
  alias Wasomi.Assessments.ResourceText

  @words_per_card_high_end 100
  @words_per_card_low_end 200
  @min_cards 5
  @max_cards 40

  def enqueue(flashcard_set_id) do
    %{"flashcard_set_id" => flashcard_set_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"flashcard_set_id" => flashcard_set_id}
      }) do
    set = Assessments.get_flashcard_set!(flashcard_set_id)

    case run(set) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Assessments.mark_flashcard_set_failed(set, inspect(reason))
        end

        {:error, reason}
    end
  end

  defp run(set) do
    Assessments.mark_flashcard_set_processing(set)

    with {:ok, drafts, source} <- draft_cards(set),
         {:ok, _count} <- Assessments.mark_flashcard_set_ready(set, drafts, source: source) do
      :ok
    end
  end

  defp draft_cards(set), do: draft_from_lesson_text(set)

  defp draft_from_lesson_text(set) do
    with {:ok, text} <- ResourceText.gather(scope(set)),
         {min_count, max_count} = card_count_range(text),
         {:ok, drafts} <-
           flashcard_generator().generate_flashcards(text,
             min_count: min_count,
             max_count: max_count
           ) do
      {:ok, drafts, :lesson_text}
    end
  end

  defp scope(%{module_id: module_id}) when not is_nil(module_id), do: {:module, module_id}
  defp scope(%{lecture_id: lecture_id}) when not is_nil(lecture_id), do: {:lecture, lecture_id}

  defp card_count_range(text) do
    word_count = text |> String.split(~r/\s+/, trim: true) |> length()

    min_count =
      word_count |> div(@words_per_card_low_end) |> max(@min_cards) |> min(@max_cards)

    max_count =
      word_count |> div(@words_per_card_high_end) |> max(min_count) |> min(@max_cards)

    {min_count, max_count}
  end

  defp flashcard_generator,
    do:
      Application.get_env(
        :wasomi,
        :flashcard_generator,
        Wasomi.Assessments.FlashcardGenerator.OpenAI
      )
end
