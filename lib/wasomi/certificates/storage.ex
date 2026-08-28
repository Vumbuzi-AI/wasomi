defmodule Wasomi.Certificates.Storage do
  @moduledoc """
  Private object storage boundary for generated certificate PDFs and their
  preview images.
  """

  @callback upload(String.t(), binary(), String.t()) :: :ok | {:error, term()}

  @doc """
  `opts` supports `:expires_in` (seconds), `:filename` — a descriptive
  filename (see `Wasomi.Certificates.certificate_filename/1`) the browser
  should save the download as, rather than guessing one from the storage
  key's own basename — and `:content_type` (default `"application/pdf"`,
  set to `"image/png"` for a preview image).
  """
  @callback signed_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
