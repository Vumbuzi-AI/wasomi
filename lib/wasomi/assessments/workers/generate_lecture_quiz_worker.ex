defmodule Wasomi.Assessments.Workers.GenerateLectureQuizWorker do
  @moduledoc """
  Drafts a lecture quiz's questions from the admin's picked resources.

  Each entry in the generation's `resource_selection` resolves to text
  independently — `"video"` reads the lecture's transcript (see
  `Wasomi.Catalog.Workers.TranscribeLecture`), anything else is a
  `Wasomi.Catalog.LectureResource` id read via the configured
  `Wasomi.Assessments.LectureResourceReader` — then every source's text is
  concatenated before a single call to the same `QuestionGenerator` the
  module-level PDF pipeline uses.

  Like `GenerateQuizFromPDFWorker`, the generation only flips to `:failed`
  on the job's last attempt.
  """

  use Oban.Worker,
    queue: :quiz_generation,
    max_attempts: 5

  alias Wasomi.Assessments
  alias Wasomi.Catalog

  def enqueue(generation_id) do
    %{"generation_id" => generation_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"generation_id" => generation_id}
      }) do
    generation = Assessments.get_lecture_quiz_generation!(generation_id)

    case run(generation) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Assessments.mark_lecture_quiz_generation_failed(generation, inspect(reason))
        end

        {:error, reason}
    end
  end

  defp run(generation) do
    Assessments.mark_lecture_quiz_generation_processing(generation)
    lecture = Assessments.get_lecture_for_generation!(generation)

    with {:ok, text} <- gather_text(generation, lecture),
         {:ok, drafts} <-
           question_generator().generate_questions(text,
             min_count: generation.question_count_requested,
             max_count: generation.question_count_requested,
             difficulty: generation.difficulty
           ),
         {:ok, _count} <-
           Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, drafts) do
      :ok
    end
  end

  defp gather_text(%{resource_selection: keys}, lecture) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, acc} ->
      case source_text(key, lecture) do
        {:ok, text} -> {:cont, {:ok, [text | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, texts} -> {:ok, texts |> Enum.reverse() |> Enum.join("\n\n---\n\n")}
      error -> error
    end
  end

  defp source_text("video", lecture) do
    case Catalog.get_lecture_transcript(lecture.id) do
      %{status: :ready, text: text} -> {:ok, text}
      %{status: status} -> {:error, {:transcript_not_ready, status}}
      nil -> {:error, :transcript_not_ready}
    end
  end

  defp source_text(resource_id, _lecture) do
    resource_id
    |> Catalog.get_lecture_resource!()
    |> resource_reader().extract_text()
  end

  defp question_generator,
    do:
      Application.get_env(
        :wasomi,
        :question_generator,
        Wasomi.Assessments.QuestionGenerator.OpenAI
      )

  defp resource_reader,
    do:
      Application.get_env(
        :wasomi,
        :lecture_resource_reader,
        Wasomi.Assessments.LectureResourceReader.Storage
      )
end
