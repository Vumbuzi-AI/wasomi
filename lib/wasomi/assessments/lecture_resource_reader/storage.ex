defmodule Wasomi.Assessments.LectureResourceReader.Storage do
  @moduledoc """
  Extracts text from a `:document` lecture resource by resolving its
  storage URL and downloading it, same `Wasomi.Storage`/`Req` combination
  `WasomiWeb.ResourceController` uses to serve it to a browser, then
  running the bytes through the configured `Wasomi.Assessments.PdfExtractor`.

  Only `:document` resources are supported — `:link` targets an arbitrary
  external page with no reliable way to extract prose from it, and `:video`
  resources are secondary videos with no transcript of their own (only a
  lecture's *primary* video gets transcribed, see
  `Wasomi.Catalog.Workers.TranscribeLecture`).
  """

  @behaviour Wasomi.Assessments.LectureResourceReader

  alias Wasomi.Catalog.LectureResource
  alias Wasomi.Storage

  @impl true
  def extract_text(%LectureResource{kind: :document, storage_key: key})
      when is_binary(key) and key != "" do
    with {:ok, url} <- Storage.download_url(key),
         {:ok, binary} <- download(url) do
      pdf_extractor().extract_text(binary)
    end
  end

  def extract_text(%LectureResource{kind: kind}), do: {:error, {:unsupported_resource_kind, kind}}

  defp download(url) do
    case Req.get(url, retry: :transient, max_retries: 3, receive_timeout: 60_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:resource_download_failed, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pdf_extractor,
    do: Application.get_env(:wasomi, :pdf_extractor, Wasomi.Assessments.PdfExtractor.PdfToText)
end
