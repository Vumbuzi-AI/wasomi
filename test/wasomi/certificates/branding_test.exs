defmodule Wasomi.Certificates.BrandingTest do
  use ExUnit.Case, async: false

  alias Wasomi.Certificates.Branding

  setup do
    original = Application.get_env(:wasomi, :certificate_branding)
    on_exit(fn -> Application.put_env(:wasomi, :certificate_branding, original) end)
    :ok
  end

  defp put_branding(config), do: Application.put_env(:wasomi, :certificate_branding, config)

  test "inlines a logo from priv/static as a base64 data URI" do
    put_branding(logo_path: "images/logo.png")

    assert "data:image/png;base64," <> encoded = Branding.assigns().logo_data_uri
    assert {:ok, _binary} = Base.decode64(encoded)
  end

  test "derives the media type from the logo's extension" do
    put_branding(logo_path: "images/logo.svg")

    assert "data:image/svg+xml;base64," <> _rest = Branding.assigns().logo_data_uri
  end

  test "falls back to no logo when the file is missing, rather than raising" do
    put_branding(logo_path: "images/does-not-exist.png")

    assert Branding.assigns().logo_data_uri == nil
  end

  test "returns no logo when none is configured" do
    put_branding([])

    assert Branding.assigns().logo_data_uri == nil
  end

  test "passes through configured contact details" do
    put_branding(
      address_lines: ["5th Floor, Nextgen Mall", "Nairobi, Kenya"],
      phone: "+254 700 000 000",
      email: "info@example.test",
      website: "www.example.test",
      socials: ["Facebook", "LinkedIn"]
    )

    assigns = Branding.assigns()

    assert assigns.address_lines == ["5th Floor, Nextgen Mall", "Nairobi, Kenya"]
    assert assigns.phone == "+254 700 000 000"
    assert assigns.email == "info@example.test"
    assert assigns.website == "www.example.test"
    assert assigns.socials == ["Facebook", "LinkedIn"]
  end

  test "drops blank and nil entries so the template renders no empty rows" do
    put_branding(
      address_lines: ["Nairobi, Kenya", "", "   ", nil],
      phone: "  ",
      email: nil,
      socials: []
    )

    assigns = Branding.assigns()

    assert assigns.address_lines == ["Nairobi, Kenya"]
    assert assigns.phone == nil
    assert assigns.email == nil
    assert assigns.socials == []
  end

  test "defaults every field when nothing is configured at all" do
    Application.delete_env(:wasomi, :certificate_branding)

    assert Branding.assigns() == %{
             logo_data_uri: nil,
             address_lines: [],
             phone: nil,
             email: nil,
             website: nil,
             socials: []
           }
  end
end
