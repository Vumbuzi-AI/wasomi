defmodule Wasomi.Catalog.LinkTextFetcher.HttpFetch do
  @moduledoc """
  Fetches a URL and strips it down to plain text via a regex-based tag
  strip — good enough for a spike; not a real readability/boilerplate
  extractor (no handling of nav/footer/ad content specifically).
  """

  @behaviour Wasomi.Catalog.LinkTextFetcher

  @max_bytes 2_000_000

  # Some sites reject requests with no (or an obviously non-browser)
  # User-Agent as bot traffic, independent of whether the content itself
  # is otherwise publicly readable — a real browser opening the same link
  # would succeed. This doesn't defeat real bot protection (e.g. Cloudflare
  # challenges), just avoids tripping the naive "no User-Agent at all"
  # checks some sites use.
  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " <>
                "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

  @impl true
  def fetch_text(url) when is_binary(url) do
    case Req.get(url,
           receive_timeout: 30_000,
           max_retries: 2,
           headers: [{"user-agent", @user_agent}]
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body |> String.slice(0, @max_bytes) |> strip_html()}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<script.*?<\/script>/si, " ")
    |> String.replace(~r/<style.*?<\/style>/si, " ")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
