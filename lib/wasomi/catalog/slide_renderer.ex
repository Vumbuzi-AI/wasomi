defmodule Wasomi.Catalog.SlideRenderer do
  @moduledoc """
  Boundary for rendering one video-overview scene's still image
  `Wasomi.Catalog.VideoAssembler` can composite with its narration audio.

  Implementations return raw encoded image bytes (PNG) at a fixed
  1280x720 (720p, 16:9) frame size, so the assembler never has to reason
  about mixed slide dimensions.

  `slide_text` is kept in the callback for implementations that want it,
  but the default `ChromicPdf` implementation no longer displays it on
  the slide — it duplicated the real closed-caption track (Mux's own
  `generated_subtitles`, attached once the video reaches Mux) while
  covering up the illustration.

  Accepts an optional `:image` opt — raw bytes from
  `Wasomi.Catalog.OverviewImageGenerator`, composited as the slide's
  background instead of the plain branded gradient. Callers that don't
  have one (generation disabled, or that scene's image generation failed)
  simply omit it; implementations must render a sensible slide either way.
  """

  @callback render(slide_text :: String.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}
end
