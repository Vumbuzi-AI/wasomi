defmodule Wasomi.Certificates.Storage.R2 do
  @moduledoc """
  Cloudflare R2 adapter using its S3-compatible API.
  """

  @behaviour Wasomi.Certificates.Storage

  @impl true
  def upload(key, data, content_type)
      when is_binary(key) and is_binary(data) and is_binary(content_type) do
    with {:ok, bucket} <- bucket(),
         {:ok, _response} <-
           bucket
           |> ExAws.S3.put_object(key, data,
             content_type: content_type,
             cache_control: "private, no-store"
           )
           |> ExAws.request() do
      :ok
    end
  end

  @impl true
  def signed_url(key, opts \\ []) when is_binary(key) do
    expires_in = Keyword.get(opts, :expires_in, 300)
    filename = Keyword.get(opts, :filename)
    content_type = Keyword.get(opts, :content_type, "application/pdf")

    with {:ok, bucket} <- bucket() do
      :s3
      |> ExAws.Config.new([])
      |> ExAws.S3.presigned_url(:get, bucket, key,
        expires_in: expires_in,
        query_params: [
          {"response-content-type", content_type},
          {"response-content-disposition", content_disposition(filename)}
        ]
      )
    end
  end

  # `attachment` alone (no filename) leaves the saved filename entirely up
  # to the browser's own guess from the URL, which lands on the object
  # key's basename — a bare id, no extension. `filename*` (RFC 5987/6266)
  # carries the real name including any non-ASCII characters; `filename`
  # stays as a plain-ASCII fallback for the handful of clients that don't
  # understand the extended form.
  defp content_disposition(nil), do: "attachment"

  defp content_disposition(filename) do
    ~s(attachment; filename="#{ascii_fallback(filename)}"; filename*=UTF-8''#{URI.encode(filename, &URI.char_unreserved?/1)})
  end

  defp ascii_fallback(filename) do
    filename
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.replace("\"", "")
  end

  defp bucket do
    case Application.get_env(:wasomi, :r2_bucket) do
      bucket when is_binary(bucket) and bucket != "" -> {:ok, bucket}
      _ -> {:error, :r2_not_configured}
    end
  end
end
