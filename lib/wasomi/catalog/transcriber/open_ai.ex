defmodule Wasomi.Catalog.Transcriber.OpenAI do
  @moduledoc """
  Transcribes lecture video via OpenAI's audio transcription endpoint.

  OpenAI's transcription endpoint takes an uploaded file, not a remote URL,
  so this downloads the (already time-limited, signed) media URL directly
  and re-uploads the bytes as multipart form data — same `Req`-direct
  approach as `Wasomi.Media.Mux` and `Wasomi.Assessments.QuestionGenerator.OpenAI`,
  no SDK.
  """

  @behaviour Wasomi.Catalog.Transcriber

  @api_url "https://api.openai.com/v1/audio/transcriptions"

  @impl true
  def transcribe(media_url) when is_binary(media_url) do
    with {:ok, api_key} <- fetch_api_key(),
         {:ok, audio} <- download(media_url) do
      request_transcription(audio, api_key)
    end
  end

  defp download(media_url) do
    case Req.get(media_url, retry: :transient, max_retries: 3, receive_timeout: 120_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:media_download_failed, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_transcription(audio, api_key) do
    Req.post(@api_url,
      headers: [{"authorization", "Bearer #{api_key}"}],
      form_multipart: [
        model: model(),
        file: {audio, filename: "lecture.mp4", content_type: "video/mp4"}
      ],
      retry: :transient,
      max_retries: 3,
      receive_timeout: 180_000
    )
    |> normalize_response()
  end

  defp normalize_response({:ok, %{status: status, body: %{"text" => text}}})
       when status in 200..299,
       do: {:ok, text}

  defp normalize_response({:ok, %{status: status, body: body}}),
    do: {:error, {:http_error, status, body}}

  defp normalize_response({:error, reason}), do: {:error, reason}

  defp model, do: Application.get_env(:wasomi, :openai_transcription_model, "whisper-1")

  defp fetch_api_key do
    case Application.get_env(:wasomi, :openai_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :openai_api_key_not_configured}
    end
  end
end
