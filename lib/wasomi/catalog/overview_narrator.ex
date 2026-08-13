defmodule Wasomi.Catalog.OverviewNarrator do
  @moduledoc """
  Boundary for synthesizing a scene's narration text into spoken audio for
  a generated video overview.

  Implementations return raw encoded audio bytes (MP3) — the caller doesn't
  care which TTS vendor or voice produced them, only that they can be
  written to disk and handed to `Wasomi.Catalog.VideoAssembler`.
  """

  @callback synthesize(text :: String.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}
end
