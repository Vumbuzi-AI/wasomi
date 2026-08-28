defmodule Wasomi.Certificates.Renderer do
  @moduledoc """
  Converts certificate presentation data into PDF bytes, and a PNG preview
  of the same design for the completion-celebration modal.
  """

  @callback render(map()) :: {:ok, binary()} | {:error, term()}
  @callback render_preview(map()) :: {:ok, binary()} | {:error, term()}
end
