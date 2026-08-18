defmodule Wasomi.Assessments.Workers.GenerateSmartTestWorker do
  @moduledoc """
  Gathers a lecture's (or module's) document/transcript text and asks the
  configured `Wasomi.Assessments.SmartTestGenerator` for exactly the question
  mix and difficulty the learner asked for. Mirrors
  `Wasomi.Assessments.Workers.GeneratePracticeSetQuestionsWorker`, including
  only flipping the test to `:failed` on the job's last Oban attempt — the
  counts come from the test row itself rather than being derived from how
  much material there is, since a Smart Test is built to the learner's spec.
  """

  use Oban.Worker,
    queue: :quiz_generation,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:smart_test_id],
      states: :incomplete
    ]

  alias Wasomi.Assessments
  alias Wasomi.Assessments.ResourceText

  def enqueue(smart_test_id) do
    %{"smart_test_id" => smart_test_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"smart_test_id" => smart_test_id}
      }) do
    smart_test = Assessments.get_smart_test!(smart_test_id)

    case run(smart_test) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Assessments.mark_smart_test_failed(smart_test, inspect(reason))
        end

        {:error, reason}
    end
  end

  defp run(smart_test) do
    Assessments.mark_smart_test_processing(smart_test)

    with {:ok, text} <- ResourceText.gather(scope(smart_test)),
         {:ok, drafts} <-
           smart_test_generator().generate_test(text,
             multiple_choice_count: smart_test.multiple_choice_count,
             short_answer_count: smart_test.short_answer_count,
             difficulty: smart_test.difficulty
           ),
         {:ok, _count} <- Assessments.mark_smart_test_ready(smart_test, drafts) do
      :ok
    end
  end

  defp scope(%{module_id: module_id}) when not is_nil(module_id), do: {:module, module_id}
  defp scope(%{lecture_id: lecture_id}) when not is_nil(lecture_id), do: {:lecture, lecture_id}

  defp smart_test_generator,
    do:
      Application.get_env(
        :wasomi,
        :smart_test_generator,
        Wasomi.Assessments.SmartTestGenerator.OpenAI
      )
end
