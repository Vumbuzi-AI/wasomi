defmodule Wasomi.Catalog.Storage.R2 do
  @moduledoc """
  Cloudflare R2 adapter (S3-compatible) for generated lecture-overview
  video output.

  Shares the same bucket as `Wasomi.Assessments.Storage.R2` and
  `Wasomi.Certificates.Storage.R2` under a `lecture-overviews/` key
  prefix.
  """

  @behaviour Wasomi.Catalog.Storage

  @impl true
  def upload(key, content) when is_binary(key) and is_binary(content) do
    with {:ok, bucket} <- bucket(),
         {:ok, _response} <-
           bucket
           |> ExAws.S3.put_object(key, content, content_type: content_type(key))
           |> ExAws.request() do
      :ok
    end
  end

  # This module stores both the generated video and its WebVTT captions
  # track under the same key prefix — a hardcoded "video/mp4" here (the
  # original, video-only version of this function) meant the captions
  # file was silently served as `video/mp4`, which browsers reject a
  # `<track>` source over with no visible error (no captions, no crash).
  defp content_type(key) do
    case Path.extname(key) do
      ".vtt" -> "text/vtt"
      ".mp4" -> "video/mp4"
      _ -> "application/octet-stream"
    end
  end

  @impl true
  def download(key) when is_binary(key) do
    with {:ok, bucket} <- bucket(),
         {:ok, %{body: body}} <- bucket |> ExAws.S3.get_object(key) |> ExAws.request() do
      {:ok, body}
    end
  end

  @impl true
  def delete(key) when is_binary(key) do
    with {:ok, bucket} <- bucket(),
         {:ok, _response} <- bucket |> ExAws.S3.delete_object(key) |> ExAws.request() do
      :ok
    end
  end

  @impl true
  def download_url(key) when is_binary(key) do
    case Application.get_env(:wasomi, :r2_public_url) do
      base when is_binary(base) and base != "" ->
        {:ok, String.trim_trailing(base, "/") <> "/" <> key}

      _ ->
        {:error, :r2_not_configured}
    end
  end

  defp bucket do
    case Application.get_env(:wasomi, :r2_bucket) do
      bucket when is_binary(bucket) and bucket != "" -> {:ok, bucket}
      _ -> {:error, :r2_not_configured}
    end
  end
end
