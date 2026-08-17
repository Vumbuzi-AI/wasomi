defmodule Wasomi.Catalog.OverviewImageGenerator do
  @moduledoc """
  Boundary for generating one video-overview scene's background illustration
  — an image relevant to what that scene's narration is actually about,
  rather than the plain branded background `Wasomi.Catalog.SlideRenderer`
  falls back to when this is unavailable.

  Implementations return raw encoded image bytes (PNG or JPEG) — the caller
  doesn't care which vendor produced them, only that they can be handed to
  `Wasomi.Catalog.SlideRenderer.render/2` as the `:image` option.
  """

  @callback generate(prompt :: String.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}
end
