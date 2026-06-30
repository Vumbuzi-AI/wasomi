defmodule Wasomi.Certificates.Storage.R2 do
  @moduledoc """
  Cloudflare R2 adapter using its S3-compatible API.
  """

  @behaviour Wasomi.Certificates.Storage

  @impl true
  def upload(key, pdf) when is_binary(key) and is_binary(pdf) do
    with {:ok, bucket} <- bucket(),
         {:ok, _response} <-
           bucket
           |> ExAws.S3.put_object(key, pdf,
             content_type: "application/pdf",
             cache_control: "private, no-store"
           )
           |> ExAws.request() do
      :ok
    end
  end

  @impl true
  def signed_url(key, opts \\ []) when is_binary(key) do
    expires_in = Keyword.get(opts, :expires_in, 300)

    with {:ok, bucket} <- bucket() do
      :s3
      |> ExAws.Config.new([])
      |> ExAws.S3.presigned_url(:get, bucket, key,
        expires_in: expires_in,
        query_params: [
          {"response-content-type", "application/pdf"},
          {"response-content-disposition", "attachment"}
        ]
      )
    end
  end

  defp bucket do
    case Application.get_env(:wasomi, :r2_bucket) do
      bucket when is_binary(bucket) and bucket != "" -> {:ok, bucket}
      _ -> {:error, :r2_not_configured}
    end
  end
end
