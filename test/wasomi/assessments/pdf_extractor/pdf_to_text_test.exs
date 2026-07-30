defmodule Wasomi.Assessments.PdfExtractor.PdfToTextTest do
  # async: false — the :pdftotext_not_available test mutates the process-wide
  # PATH env var, which would race other async tests shelling out to pdftotext.
  use ExUnit.Case, async: false

  alias Wasomi.Assessments.PdfExtractor.PdfToText

  @minimal_pdf """
  %PDF-1.4
  1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
  2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
  3 0 obj<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/MediaBox[0 0 200 200]/Contents 5 0 R>>endobj
  4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
  5 0 obj<</Length 44>>
  stream
  BT /F1 24 Tf 20 100 Td (Hello World) Tj ET
  endstream
  endobj
  trailer<</Size 6/Root 1 0 R>>
  %%EOF
  """

  test "extracts text from a valid PDF" do
    assert {:ok, text} = PdfToText.extract_text(@minimal_pdf)
    assert text =~ "Hello World"
  end

  test "returns pdftotext's stderr diagnostics on a malformed PDF" do
    assert {:error, {:pdftotext_failed, status, error_output}} =
             PdfToText.extract_text("not a pdf at all")

    assert status != 0
    assert error_output =~ "Syntax Error"
  end

  test "returns :pdftotext_not_available when the binary is missing" do
    original_path = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      assert {:error, {:pdftotext_not_available, _}} = PdfToText.extract_text(@minimal_pdf)
    after
      System.put_env("PATH", original_path)
    end
  end
end
