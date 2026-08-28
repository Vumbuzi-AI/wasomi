defmodule Wasomi.Certificates.Renderer.ChromicPdf do
  @moduledoc """
  Renders the certificate HEEx template to PDF bytes via headless Chrome.
  """

  @behaviour Wasomi.Certificates.Renderer

  alias Wasomi.Certificates.Template

  # A4 landscape, in inches (11.69x8.27in), with no default Chrome print
  # margins — the certificate design carries its own internal padding and is
  # meant to sit full-bleed on the page.
  #
  # `landscape` is deliberately omitted: Chrome's `Page.printToPDF` swaps
  # paperWidth/paperHeight when `landscape: true` is combined with explicit
  # dimensions, which would rotate this already-wide page back to portrait.
  @print_options %{
    printBackground: true,
    paperWidth: 11.69,
    paperHeight: 8.27,
    marginTop: 0,
    marginBottom: 0,
    marginLeft: 0,
    marginRight: 0
  }

  # The template embeds its fonts as base64 data URIs (see Template), so this
  # no longer waits on a network fetch — but decoding/rasterizing an embedded
  # webfont still isn't synchronous with page load, and printing before it
  # settles would silently fall back to a generic system font.
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
