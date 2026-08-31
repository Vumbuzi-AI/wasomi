defmodule Wasomi.Receipts.Renderer.ChromicPdf do
  @moduledoc """
  Renders the receipt HEEx template to PDF bytes via headless Chrome.
  """

  @behaviour Wasomi.Receipts.Renderer

  alias Wasomi.Receipts.Template

  # A4 portrait, in inches, with generous margins so the document has the
  # breathing room of a printed statement rather than a web page.
  @print_options %{
    printBackground: true,
    paperWidth: 8.27,
    paperHeight: 11.69,
    marginTop: 0.85,
    marginBottom: 0.85,
    marginLeft: 0.85,
    marginRight: 0.85
  }

  # The template embeds its fonts as base64 data URIs; block the print on
  # `document.fonts.ready` so Outfit is rasterised, not a fallback face.
  @evaluate %{expression: "document.fonts.ready"}

  @impl true
  def render(assigns) do
    html = Template.render_html(assigns)

    case ChromicPDF.print_to_pdf({:html, html}, print_to_pdf: @print_options, evaluate: @evaluate) do
      {:ok, base64_pdf} -> {:ok, Base.decode64!(base64_pdf)}
      other -> {:error, other}
    end
  rescue
    error -> {:error, error}
  end
end
