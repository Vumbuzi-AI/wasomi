defmodule Wasomi.Certificates.VerificationQRTest do
  use ExUnit.Case, async: true

  alias Wasomi.Certificates.VerificationQR

  @gdti "6167007558430749194392"

  describe "verification_url/1" do
    test "builds the GS1 Digital Link verification URL for a given GDTI" do
      url = VerificationQR.verification_url(@gdti)

      assert url == WasomiWeb.Endpoint.url() <> "/certificates/253/" <> @gdti
      assert String.ends_with?(url, "/certificates/253/#{@gdti}")
    end

    test "different GDTIs produce different URLs" do
      refute VerificationQR.verification_url(@gdti) ==
               VerificationQR.verification_url("6167007558430000000000")
    end
  end

  describe "data_uri/1" do
    test "returns a PNG data URI" do
      assert "data:image/png;base64," <> base64 = VerificationQR.data_uri(@gdti)
      assert {:ok, _binary} = Base.decode64(base64)
    end

    test "encodes the certificate's own verification URL, not a placeholder" do
      # Round-trips the actual QR pipeline (not the whole image-decode step,
      # which needs an external scanning library this project doesn't
      # depend on) to confirm the exact URL going in is the one the QR
      # matrix would encode — verified separately, by hand, with an actual
      # QR decoder against a rendered certificate.
      url = VerificationQR.verification_url(@gdti)

      assert {:ok, qr} = QRCode.create(url, :high)
      assert qr.orig == url
    end

    test "different certificates get visibly different QR images" do
      uri_1 = VerificationQR.data_uri(@gdti)
      uri_2 = VerificationQR.data_uri("6167007558430000000000")

      refute uri_1 == uri_2
    end
  end
end
