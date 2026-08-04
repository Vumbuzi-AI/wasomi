defmodule Wasomi.Certificates.Renderer.ChromicPdf do
  @moduledoc """
  Renders the certificate HEEx template to PDF bytes via headless Chrome.
  """

  @behaviour Wasomi.Certificates.Renderer

  alias Wasomi.Certificates.Template

  # 16:9 widescreen, in inches (13.333x7.5in == 1280x720px @96dpi), with no
  # default Chrome print margins — the certificate is a full-bleed design
  # meant for on-screen viewing/sharing, not a printed A4/Letter page.
  #
  # `landscape` is deliberately omitted: Chrome's `Page.printToPDF` swaps
  # paperWidth/paperHeight when `landscape: true` is combined with explicit
  # dimensions, which would rotate this already-wide page back to portrait.
  @print_options %{
    printBackground: true,
    paperWidth: 13.333,
    paperHeight: 7.5,
    marginTop: 0,
    marginBottom: 0,
    marginLeft: 0,
    marginRight: 0
  }

  # The template loads Google Fonts over the network; without this, Chrome can
  # print before the webfont request finishes and silently fall back to a
  # generic system font.
  @evaluate %{expression: "document.fonts.ready"}

  @impl true
  def render(assigns) do
    html = Template.render_html(assigns)

    with {:ok, base64_pdf} <-
           ChromicPDF.print_to_pdf({:html, html},
             print_to_pdf: @print_options,
             evaluate: @evaluate
           ) do
      {:ok, Base.decode64!(base64_pdf)}
    end
  end
end
