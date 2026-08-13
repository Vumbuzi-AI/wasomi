defmodule Wasomi.Catalog.LinkTextFetcher do
  @moduledoc """
  Boundary for turning a `:link`-kind `LectureResource`'s URL into plain
  text usable as video-overview source material.
  """

  @callback fetch_text(url :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
