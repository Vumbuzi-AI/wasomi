defmodule Wasomi.Catalog.Workers.TranscribeLecture do
  @moduledoc """
  Transcribes a lecture's primary video once its Mux asset is ready, so a
  slow speech-to-text call never blocks the admin's save request.

  The transcript only flips to `:failed` on the job's last Oban attempt —
  earlier failures leave it `:processing` so an admin re-checking mid-retry
  doesn't see a false "failed" moments before a retry quietly succeeds.
  """

  use Oban.Worker,
    queue: :transcription,
    max_attempts: 5

  alias Wasomi.Catalog

  def enqueue(lecture_id) do
    %{"lecture_id" => lecture_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{"lecture_id" => lecture_id}
      }) do
    case run(lecture_id) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Catalog.upsert_lecture_transcript(lecture_id, %{
            status: :failed,
            error: inspect(reason)
          })
        end

        {:error, reason}
    end
  end

  defp run(lecture_id) do
    lecture = Catalog.get_lecture!(lecture_id)
    Catalog.upsert_lecture_transcript(lecture_id, %{status: :processing})

    with {:ok, media_url} <- media().download_url(lecture),
         {:ok, text} <- transcriber().transcribe(media_url),
         {:ok, _transcript} <-
           Catalog.upsert_lecture_transcript(lecture_id, %{status: :ready, text: text, error: nil}) do
      :ok
    end
  end

  defp media, do: Wasomi.Media.configured_adapter()

  defp transcriber,
    do: Application.get_env(:wasomi, :transcriber, Wasomi.Catalog.Transcriber.OpenAI)
end
