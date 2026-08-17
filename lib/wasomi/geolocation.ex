defmodule Wasomi.Geolocation do
  @moduledoc """
  Boundary for resolving a public IP address to a country code.
  """

  @callback country_code(String.t()) :: {:ok, String.t()} | {:error, term()}
end
