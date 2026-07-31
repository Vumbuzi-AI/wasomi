defmodule Wasomi.Assessments.Storage.R2 do
  @moduledoc """
  Cloudflare R2 adapter (S3-compatible) for transient quiz-generation source PDFs.

  Shares the same bucket as `Wasomi.Certificates.Storage.R2` under a
  `quiz-generations/` key prefix — these PDFs are short-lived worker input,
  not a durable asset, so callers delete them once a generation finishes.
  """

  @behaviour Wasomi.Assessments.Storage

  @impl true
  def upload(key, pdf) when is_binary(key) and is_binary(pdf) do
    with {:ok, bucket} <- bucket(),
         {:ok, _response} <-
           bucket
           |> ExAws.S3.put_object(key, pdf, content_type: "application/pdf")
           |> ExAws.request() do
      :ok
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

  defp bucket do
    case Application.get_env(:wasomi, :r2_bucket) do
      bucket when is_binary(bucket) and bucket != "" -> {:ok, bucket}
      _ -> {:error, :r2_not_configured}
    end
  end
end
