defmodule Wasomi.Payments.Provider do
  @moduledoc """
  Boundary for hosted payment providers.
  """

  alias Wasomi.Payments.Payment

  @callback initiate(Payment.t()) :: {:ok, map()} | {:error, term()}
  @callback verify(String.t()) :: {:ok, map()} | {:error, term()}
end
