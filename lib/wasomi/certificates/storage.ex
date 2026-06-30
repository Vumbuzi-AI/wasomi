defmodule Wasomi.Certificates.Storage do
  @moduledoc """
  Private object storage boundary for generated certificate PDFs.
  """

  @callback upload(String.t(), binary()) :: :ok | {:error, term()}
  @callback signed_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
