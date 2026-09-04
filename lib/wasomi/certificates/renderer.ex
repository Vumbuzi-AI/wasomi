defmodule Wasomi.Certificates.Renderer do
  @moduledoc """
  Converts certificate presentation data into PDF bytes, and a PNG preview
  of the same design for the completion-celebration modal.
  """

  @callback render(map()) :: {:ok, binary()} | {:error, term()}
  @callback render_preview(map()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Whether the renderer can produce output right now (e.g. its browser pool
  is up). Optional — a renderer that omits it is assumed always available.
  """
  @callback available?() :: boolean()
  @optional_callbacks available?: 0
end
