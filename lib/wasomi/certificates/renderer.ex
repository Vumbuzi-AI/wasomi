defmodule Wasomi.Certificates.Renderer do
  @moduledoc """
  Converts certificate presentation data into PDF bytes.
  """

  @callback render(map()) :: {:ok, binary()} | {:error, term()}
end
