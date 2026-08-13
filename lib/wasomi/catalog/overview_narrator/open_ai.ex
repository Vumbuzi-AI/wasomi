defmodule Wasomi.Catalog.OverviewNarrator.OpenAI do
  @moduledoc """
  Synthesizes narration audio via OpenAI's `/audio/speech` endpoint.

  Unlike the Chat Completions adapters elsewhere in this app, this endpoint
  returns raw audio bytes directly (not a JSON envelope), so there's no
  response body to parse — just the encoded MP3.
  """

  @behaviour Wasomi.Catalog.OverviewNarrator

  @api_url "https://api.openai.com/v1/audio/speech"
  @default_model "tts-1"
  @default_voice "alloy"

  @impl true
  def synthesize(text, opts \\ []) when is_binary(text) do
    voice = Keyword.get(opts, :voice, default_voice())

    body = %{
      "model" => model(),
      "voice" => voice,
      "input" => text,
      "response_format" => "mp3"
    }

    with {:ok, api_key} <- api_key() do
      response =
        Req.post(@api_url,
          json: body,
          headers: [
            {"Content-Type", "application/json"},
            {"Authorization", "Bearer #{api_key}"}
          ],
          retry: :transient,
          max_retries: 5,
          receive_timeout: 120_000
        )

      case response do
        {:ok, %{status: 200, body: audio}} when is_binary(audio) ->
          {:ok, audio}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp api_key do
    case Application.get_env(:wasomi, :openai_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :openai_api_key_not_configured}
    end
  end

  defp model, do: Application.get_env(:wasomi, :openai_tts_model, @default_model)
  defp default_voice, do: Application.get_env(:wasomi, :openai_tts_voice, @default_voice)
end
