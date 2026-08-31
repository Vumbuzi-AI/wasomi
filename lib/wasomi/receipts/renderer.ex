defmodule Wasomi.Receipts.Renderer do
  @moduledoc """
  Converts receipt presentation data into PDF bytes. Swapped for a mock in
  tests so nothing there depends on a headless Chrome binary.
  """

  @callback render(map()) :: {:ok, binary()} | {:error, term()}
end
