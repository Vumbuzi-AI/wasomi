defmodule Wasomi.Catalog.VideoAssembler do
  @moduledoc """
  Boundary for assembling a list of `%{image_path:, audio_path:}` scenes
  (already written to disk by the caller) into a single narrated MP4.

  A behaviour — like the other adapters in this module tree — purely so
  worker tests never have to shell out to a real `ffmpeg` binary. See
  `Wasomi.Catalog.VideoAssembler.Ffmpeg` for the concrete adapter.
  """

  @type scene :: %{image_path: Path.t(), audio_path: Path.t()}

  @callback assemble(scenes :: [scene()], output_path :: Path.t()) ::
              {:ok, Path.t()} | {:error, term()}
end
