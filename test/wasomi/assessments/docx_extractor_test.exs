defmodule Wasomi.Assessments.DocxExtractorTest do
  use ExUnit.Case, async: true

  alias Wasomi.Assessments.DocxExtractor.Unzip

  describe "extract_text/1" do
    test "extracts paragraphs and text runs from valid docx binary" do
      files = [
        {~c"word/document.xml",
         """
         <?xml version="1.0" encoding="UTF-8"?>
         <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
           <w:body>
             <w:p>
               <w:t>First paragraph</w:t>
               <w:t> continued &amp; extended.</w:t>
             </w:p>
             <w:p>
               <w:t>Second paragraph with &lt;special&gt; characters.</w:t>
             </w:p>
           </w:body>
         </w:document>
         """}
      ]

      {:ok, {~c"mem", docx_binary}} = :zip.create(~c"mem", files, [:memory])

      assert {:ok, text} = Unzip.extract_text(docx_binary)

      assert text ==
               "First paragraph continued & extended.\n\nSecond paragraph with <special> characters."
    end

    test "returns error for missing word/document.xml in zip" do
      files = [{~c"other.txt", "hello"}]
      {:ok, {~c"mem", zip_binary}} = :zip.create(~c"mem", files, [:memory])

      assert {:error, :missing_word_document_xml} = Unzip.extract_text(zip_binary)
    end

    test "returns error for invalid zip binary" do
      assert {:error, {:invalid_docx_zip, _reason}} = Unzip.extract_text("not a zip binary")
    end
  end
end
