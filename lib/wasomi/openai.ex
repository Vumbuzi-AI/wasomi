defmodule Wasomi.OpenAI do
  @moduledoc """
  Small OpenAI connectivity diagnostic for development and operations.

  `check/0` verifies that the configured API key is accepted and can access
  the configured model without generating tokens. `probe/0` additionally
  performs a tiny Responses API generation to verify an end-to-end call.

  Neither function logs or returns the API key.
  """

  @api_url "https://api.openai.com/v1"
  @default_model "gpt-5.4-mini"

  @doc """
  Validates the API key and configured model without creating a completion.

  Run with:

      mix run -e 'IO.inspect(Wasomi.OpenAI.check())'
  """
  def check do
    with {:ok, key} <- fetch_api_key(),
         {:ok, body} <- request(:get, "/models/#{URI.encode(model())}", key) do
      {:ok, %{authenticated: true, model: body["id"] || model()}}
    end
  end

  @doc """
  Makes a minimal Responses API request and confirms that generation works.

  This request uses a small number of billable tokens.

      mix run -e 'IO.inspect(Wasomi.OpenAI.probe())'
  """
  def probe do
    with {:ok, key} <- fetch_api_key(),
         {:ok, body} <-
           request(:post, "/responses", key,
             json: %{
               model: model(),
               input: "Reply with exactly: OK",
               max_output_tokens: 16
             }
           ) do
      {:ok,
       %{
         authenticated: true,
         request_id: body["id"],
         model: body["model"] || model(),
         status: body["status"]
       }}
    end
  end

  defp request(method, path, key, options \\ []) do
    Req.request(
      [
        method: method,
        url: api_url() <> path,
        headers: [
          {"authorization", "Bearer " <> key},
          {"content-type", "application/json"}
        ],
        retry: :transient,
        max_retries: 2,
        receive_timeout: 30_000
      ] ++ Application.get_env(:wasomi, :openai_check_req_options, []) ++ options
    )
    |> normalize_response()
  end

  defp normalize_response({:ok, %{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp normalize_response({:ok, %{status: status, body: %{"error" => error}}}),
    do: {:error, {:openai, status, sanitize_error(error)}}

  defp normalize_response({:ok, %{status: status}}),
    do: {:error, {:openai, status, "unexpected response"}}

  defp normalize_response({:error, reason}), do: {:error, {:transport, reason}}

  defp sanitize_error(error) when is_map(error),
    do: Map.take(error, ["message", "type", "code", "param"])

  defp sanitize_error(_), do: %{"message" => "unknown OpenAI error"}

  defp fetch_api_key do
    case Application.get_env(:wasomi, :openai_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :openai_api_key_not_configured}
    end
  end

  defp model, do: Application.get_env(:wasomi, :openai_model, @default_model)
  defp api_url, do: Application.get_env(:wasomi, :openai_api_url, @api_url)
end
