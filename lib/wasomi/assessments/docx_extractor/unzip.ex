defmodule Wasomi.Assessments.DocxExtractor.Unzip do
  @moduledoc """
  Extracts text from a `.docx` binary document by unzipping `word/document.xml`
  in memory and extracting paragraph text runs.
  """

  @behaviour Wasomi.Assessments.DocxExtractor

  @impl true
  def extract_text(docx_binary) when is_binary(docx_binary) do
    case :zip.extract(docx_binary, [:memory]) do
      {:ok, unzipped} ->
        case find_document_xml(unzipped) do
          nil ->
            {:error, :missing_word_document_xml}

          xml_content ->
            text = parse_xml_text(xml_content)
            {:ok, text}
        end

      {:error, reason} ->
        {:error, {:invalid_docx_zip, reason}}
    end
  end

  defp find_document_xml(unzipped) do
    Enum.find_value(unzipped, fn
      {~c"word/document.xml", content} -> content
      {"word/document.xml", content} -> content
      _ -> nil
    end)
  end

  defp parse_xml_text(xml_content) do
    Regex.scan(~r/<w:p\b[^>]*>(.*?)<\/w:p>/s, xml_content)
    |> Enum.map(fn [_, p_content] ->
      Regex.scan(~r/<w:t\b[^>]*>(.*?)<\/w:t>/s, p_content)
      |> Enum.map_join("", fn [_, t_text] -> decode_xml_entities(t_text) end)
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp decode_xml_entities(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> then(
      &Regex.replace(~r/&#x([0-9a-fA-F]+);/, &1, fn full, hex ->
        codepoint_to_utf8(String.to_integer(hex, 16), full)
      end)
    )
    |> then(
      &Regex.replace(~r/&#(\d+);/, &1, fn full, dec ->
        codepoint_to_utf8(String.to_integer(dec), full)
      end)
    )
    |> String.replace("&amp;", "&")
  end

  defp codepoint_to_utf8(cp, original) when cp in 0..0x10FFFF do
    <<cp::utf8>>
  rescue
    ArgumentError -> original
  end

  defp codepoint_to_utf8(_cp, original), do: original
end
