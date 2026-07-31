defmodule Wasomi.Assessments.PdfExtractor.PdfToText do
  @moduledoc """
  Shells out to the `pdftotext` CLI (poppler-utils) for text extraction.

  No actively-maintained pure-Elixir PDF-text library is mature enough to
  depend on, so this adapter follows the same shape as every other external
  boundary in this codebase (a behaviour + a swappable adapter) but reaches
  for a well-known system tool instead of a hex dependency. Requires
  poppler-utils (`pdftotext`) available on the runtime image.
  """

  @behaviour Wasomi.Assessments.PdfExtractor

  @impl true
  def extract_text(pdf_binary) when is_binary(pdf_binary) do
    path = Path.join(System.tmp_dir!(), "wasomi-pdf-#{System.unique_integer([:positive])}.pdf")

    try do
      case File.write(path, pdf_binary) do
        :ok -> run_pdftotext(path)
        {:error, reason} -> {:error, {:temp_file_write_failed, reason}}
      end
    rescue
      e in ErlangError -> {:error, {:pdftotext_not_available, e}}
    after
      File.rm(path)
    end
  end

  defp run_pdftotext(path) do
    case System.cmd("pdftotext", [path, "-"], stderr_to_stdout: true) do
      {text, 0} -> {:ok, text}
      {error_output, status} -> {:error, {:pdftotext_failed, status, error_output}}
    end
  end
end
