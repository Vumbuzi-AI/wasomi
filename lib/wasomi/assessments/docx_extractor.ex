defmodule Wasomi.Assessments.DocxExtractor do
  @moduledoc """
  Boundary for turning an uploaded Microsoft Word (.docx) document's raw bytes into plain text.
  """

  @callback extract_text(binary()) :: {:ok, String.t()} | {:error, term()}
end
