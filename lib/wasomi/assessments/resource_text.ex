defmodule Wasomi.Assessments.ResourceText do
  @moduledoc """
  Gathers extractable text for the learner-triggered Flashcards/Extra-
  questions/Study-guide generators, scoped to a whole module, a single
  lecture, or one individual document resource.

  Unlike `Wasomi.Assessments.Workers.GenerateQuizFromPDFWorker`'s
  admin-picked `resource_selection`, self-study generation has no admin in
  the loop to pick sources — it always draws on *every* `:document`
  resource and every `:ready` video transcript available within the given
  scope. Mirrors that worker's `source_text/1` dispatch
  (`"video:<lecture_id>"` / `"doc:<resource_id>"`) and text-joining
  exactly, so both pipelines fail/behave the same way for the same
  underlying resource.
  """

  alias Wasomi.Catalog

  @doc """
  Returns `{:ok, text}` (every source joined with `"\\n\\n---\\n\\n"`) or
  `{:error, reason}` if the scope has nothing extractable yet.
  """
  def gather({:module, module_id}) do
    module_id
    |> module_source_keys()
    |> gather_text()
  end

  def gather({:lecture, lecture_id}) do
    lecture_id
    |> Catalog.get_lecture!()
    |> lecture_source_keys()
    |> gather_text()
  end

  # The narrowest scope: one document, on its own. A learner asking for notes on
  # a single PDF gets notes on that PDF — the rest of the lesson's material is
  # deliberately not folded in, which is the whole point of the scope.
  def gather({:resource, resource_id}) do
    gather_text(["doc:#{resource_id}"])
  end

  defp module_source_keys(module_id) do
    module_id
    |> Catalog.list_lectures_for_module()
    |> Enum.flat_map(&lecture_source_keys/1)
  end

  defp lecture_source_keys(lecture) do
    lecture = Catalog.preload_lecture_content(lecture)

    document_keys =
      lecture.resources
      |> Enum.filter(&(&1.kind == :document))
      |> Enum.map(&"doc:#{&1.id}")

    case Catalog.get_lecture_transcript(lecture.id) do
      %{status: :ready} -> ["video:#{lecture.id}" | document_keys]
      _ -> document_keys
    end
  end

  defp gather_text([]), do: {:error, :no_resources_available}

  defp gather_text(keys) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, acc} ->
      case source_text(key) do
        {:ok, text} -> {:cont, {:ok, [text | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, texts} -> {:ok, texts |> Enum.reverse() |> Enum.join("\n\n---\n\n")}
      error -> error
    end
  end

  defp source_text("video:" <> lecture_id_str) do
    case Integer.parse(lecture_id_str) do
      {lecture_id, ""} ->
        case Catalog.get_lecture_transcript(lecture_id) do
          %{status: :ready, text: text} -> {:ok, text}
          %{status: status} -> {:error, {:transcript_not_ready, status}}
          nil -> {:error, :transcript_not_ready}
        end

      _ ->
        {:error, :invalid_resource_key}
    end
  end

  defp source_text("doc:" <> resource_id_str) do
    case Integer.parse(resource_id_str) do
      {resource_id, ""} ->
        case Catalog.get_lecture_resource(resource_id) do
          nil ->
            {:error, :resource_not_found}

          %{kind: :document} = resource ->
            resource_reader().extract_text(resource)

          %{kind: kind} ->
            {:error, {:unsupported_resource_kind, kind}}
        end

      _ ->
        {:error, :invalid_resource_key}
    end
  end

  defp source_text(_key), do: {:error, :invalid_resource_key}

  defp resource_reader,
    do:
      Application.get_env(
        :wasomi,
        :lecture_resource_reader,
        Wasomi.Assessments.LectureResourceReader.Storage
      )
end
