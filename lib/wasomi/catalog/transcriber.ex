defmodule Wasomi.Catalog.Transcriber do
  @moduledoc """
  Behaviour for turning a lecture's video into transcript text.

  Swappable via the `:transcriber` config key, same pattern as
  `Wasomi.Assessments.QuestionGenerator` — production/dev point at a real
  speech-to-text API, tests point at `Wasomi.TranscriberMock`.
  """

  @callback transcribe(media_url :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
