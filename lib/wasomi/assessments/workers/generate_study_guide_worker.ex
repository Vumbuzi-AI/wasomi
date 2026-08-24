defmodule Wasomi.Assessments.Workers.GenerateStudyGuideWorker do
  @moduledoc """
  Gathers a lecture's (or module's) document/transcript text and asks the
  configured `Wasomi.Assessments.StudyGuideGenerator` to write the guide the
  learner briefed. Mirrors
  `Wasomi.Assessments.Workers.GenerateSmartTestWorker`, including only
  flipping the guide to `:failed` on the job's last Oban attempt — the style,
  depth and focus come from the guide row itself, since a guide is written to
  the learner's own spec.
  """

  use Oban.Worker,
    queue: :quiz_generation,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:study_guide_id],
      states: :incomplete
    ]

  alias Wasomi.Assessments
  alias Wasomi.Assessments.ResourceText
  alias Wasomi.Catalog

  def enqueue(study_guide_id) do
    %{"study_guide_id" => study_guide_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"study_guide_id" => study_guide_id}
      }) do
    study_guide = Assessments.get_study_guide!(study_guide_id)

    case run(study_guide) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Assessments.mark_study_guide_failed(study_guide, inspect(reason))
        end

        {:error, reason}
    end
  end

  defp run(study_guide) do
    Assessments.mark_study_guide_processing(study_guide)

    with {:ok, text} <- ResourceText.gather(scope(study_guide)),
         {:ok, draft} <-
           study_guide_generator().generate_guide(text,
             style: study_guide.style,
             depth: study_guide.depth,
             reading_level: study_guide.reading_level,
             include_key_terms: study_guide.include_key_terms,
             include_examples: study_guide.include_examples,
             focus: study_guide.focus,
             scope_label: scope_label(study_guide)
           ),
         {:ok, _count} <- Assessments.mark_study_guide_ready(study_guide, draft) do
      :ok
    end
  end

  defp scope(%{module_id: module_id}) when not is_nil(module_id), do: {:module, module_id}
  defp scope(%{lecture_id: lecture_id}) when not is_nil(lecture_id), do: {:lecture, lecture_id}

  defp scope(%{lecture_resource_id: resource_id}) when not is_nil(resource_id),
    do: {:resource, resource_id}

  # Only used to title the document. Safe to fetch unguarded: the scope rows
  # cascade-delete their guides, so a guide that loaded still has its scope.
  defp scope_label(%{module_id: module_id}) when not is_nil(module_id),
    do: Catalog.get_course_module!(module_id).title

  defp scope_label(%{lecture_id: lecture_id}) when not is_nil(lecture_id),
    do: Catalog.get_lecture!(lecture_id).title

  defp scope_label(%{lecture_resource_id: resource_id}),
    do: Catalog.get_lecture_resource(resource_id).name

  defp study_guide_generator,
    do:
      Application.get_env(
        :wasomi,
        :study_guide_generator,
        Wasomi.Assessments.StudyGuideGenerator.OpenAI
      )
end
