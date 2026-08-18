defmodule Wasomi.ExAws.HttpClient do
  @moduledoc """
  ExAws HTTP client backed by the app's existing `Wasomi.Finch` pool.

  ExAws defaults to `:hackney`, but hackney 4.x pulls in the `quic` package,
  which needs a newer OTP than some deploy targets have. Finch is already
  supervised in `Wasomi.Application`, so reusing it drops that dependency
  chain entirely.
  """

  @behaviour ExAws.Request.HttpClient

  @default_timeout 30_000

  @impl ExAws.Request.HttpClient
  def request(method, url, body, headers, http_opts) do
    opts = [receive_timeout: timeout(http_opts)]

    method
    |> Finch.build(url, headers, body)
    |> Finch.request(Wasomi.Finch, opts)
    |> case do
      {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status_code: status, headers: resp_headers, body: resp_body}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  # ExAws passes hackney-style options through; `:recv_timeout` is the only one
  # this app relies on, so translate it and ignore the rest.
  defp timeout(http_opts) when is_list(http_opts),
    do: Keyword.get(http_opts, :recv_timeout, @default_timeout)

  defp timeout(_http_opts), do: @default_timeout
end
