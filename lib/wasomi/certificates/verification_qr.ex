defmodule Wasomi.Certificates.VerificationQR do
  @moduledoc """
  Builds the QR code printed on every certificate — a code that encodes the
  public verification URL for that specific certificate (the GS1 Digital
  Link shape decided in TODO.md's GDTI section: `/certificates/253/:gdti`).

  `:high` error correction is used deliberately: certificates are physical,
  printed documents (creased, photocopied, phone-photographed at an angle),
  not clean digital-only codes, so it's worth the denser matrix to keep
  scanning reliable.

  QR generation failing is treated the same way `Branding.asset_data_uri/1`
  already treats a missing logo file: `data_uri/1` returns `nil` rather
  than raising, so a QR problem never blocks certificate issuance —
  `Template` already falls back to its CSS placeholder when `qr_data_uri`
  is nil.
  """

  @doc """
  The public verification URL a certificate's QR code encodes.
  """
  @spec verification_url(String.t()) :: String.t()
  def verification_url(gdti), do: WasomiWeb.Endpoint.url() <> "/certificates/253/" <> gdti

  @doc """
  A `data:image/png;base64,...` URI encoding a QR for `gdti`'s verification
  URL, or `nil` if QR generation fails for any reason.
  """
  @spec data_uri(String.t()) :: String.t() | nil
  def data_uri(gdti) do
    gdti
    |> verification_url()
    |> QRCode.create(:high)
    |> QRCode.render(:png)
    |> QRCode.to_base64()
    |> case do
      {:ok, base64} -> "data:image/png;base64," <> base64
      {:error, _reason} -> nil
    end
  end
end
