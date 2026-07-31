defmodule Wasomi.Assessments.PdfExtractor do
  @moduledoc """
  Boundary for turning an uploaded PDF's raw bytes into plain text.

  A behaviour so tests never shell out to a real PDF tool — see
  `Wasomi.Assessments.PdfExtractor.PdfToText` for the concrete adapter and
  why it shells out rather than depending on a hex package.
  """

  @callback extract_text(binary()) :: {:ok, String.t()} | {:error, term()}
end
