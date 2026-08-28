defmodule Wasomi.Certificates.Storage do
  @moduledoc """
  Private object storage boundary for generated certificate PDFs.
  """

  @callback upload(String.t(), binary()) :: :ok | {:error, term()}

  @doc """
  `opts` supports `:expires_in` (seconds) and `:filename` — a descriptive
  filename (see `Wasomi.Certificates.certificate_filename/1`) the browser
  should save the download as, rather than guessing one from the storage
  key's own basename.
  """
  @callback signed_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
