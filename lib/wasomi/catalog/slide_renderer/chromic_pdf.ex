defmodule Wasomi.Catalog.SlideRenderer.ChromicPdf do
  @moduledoc """
  Renders a slide as a screenshot of a minimal standalone HTML page via
  headless Chrome — the same `ChromicPDF` process already started for
  certificate PDF rendering (`Wasomi.Certificates.Renderer.ChromicPdf`),
  used here for `capture_screenshot/2` instead of `print_to_pdf/2`.
  """

  @behaviour Wasomi.Catalog.SlideRenderer

  @width 1280
  @height 720

  # The explicit `clip` (not the natural content size) is what makes every
  # slide the same fixed frame size regardless of how much text it holds —
  # `full_page: true` is still needed alongside it, though: without it,
  # ChromicPDF never resizes Chrome's (small default) viewport at all, so a
  # 1280x720 clip mostly falls outside the actual rendered viewport and
  # comes back blank. `full_page: true` resizes the viewport to the page's
  # CSS content size (which our fixed `width`/`height` pins to 1280x720
  # anyway) — our own `clip` below still governs the exact capture region.
  @capture_screenshot %{
    format: "png",
    clip: %{x: 0, y: 0, width: @width, height: @height, scale: 1}
  }

  @impl true
  def render(_slide_text, opts \\ []) do
    html = html(Keyword.get(opts, :image))

    case ChromicPDF.capture_screenshot({:html, html},
           full_page: true,
           capture_screenshot: @capture_screenshot
         ) do
      {:ok, base64_png} -> {:ok, Base.decode64!(base64_png)}
      other -> {:error, other}
    end
  rescue
    error -> {:error, error}
  end

  # Wasomi's own brand tokens (assets/tailwind.config.js is the source of
  # truth, per design.md — kept in sync by hand since this HTML is rendered
  # standalone by headless Chrome, outside the Tailwind build), used only
  # for the no-image fallback background now that there's no text on the
  # slide to brand.
  @primary "#f97316"
  @dark "#0a0a0a"

  # No on-screen text at all now — it duplicated the real closed-caption
  # track (Mux's own `generated_subtitles`) while also covering up the
  # illustration itself, which is the whole point of the slide now that
  # the image is grounded in the scene's actual content rather than a
  # generic backdrop.
  defp html(image) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          html, body {
            margin: 0;
            width: #{@width}px;
            height: #{@height}px;
            background: radial-gradient(circle at 60% 30%, #1a1208 0%, #{@dark} 55%);
            position: relative;
            overflow: hidden;
          }
          .bg-image {
            position: absolute;
            inset: 0;
            background-image: url(#{image_data_uri(image)});
            background-size: cover;
            background-position: center;
          }
          .glow {
            position: absolute;
            width: 640px;
            height: 640px;
            border-radius: 9999px;
            background: radial-gradient(circle, #{@primary}59 0%, #{@primary}00 70%);
            top: -180px;
            right: -140px;
          }
        </style>
      </head>
      <body>
        #{background_layers(image)}
      </body>
    </html>
    """
  end

  defp background_layers(nil), do: ~s(<div class="glow"></div>)
  defp background_layers(_image), do: ~s(<div class="bg-image"></div>)

  defp image_data_uri(nil), do: ""

  defp image_data_uri(image) when is_binary(image),
    do: "data:image/png;base64,#{Base.encode64(image)}"
end
