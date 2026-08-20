defmodule Wasomi.Certificates.TemplateTest do
  use ExUnit.Case, async: true

  alias Wasomi.Certificates.Template

  @base_assigns %{
    learner_name: "Alex J. Mercer",
    title: "Advanced Full-Stack Web Development",
    type_label: "Course Achievement",
    issued_on: "August 4, 2026",
    serial_number: "GSI-2026-8942"
  }

  test "renders the learner, title, serial, and date" do
    html = Template.render_html(@base_assigns)

    assert html =~ "Alex J. Mercer"
    assert html =~ "Advanced Full-Stack Web Development"
    assert html =~ "GSI-2026-8942"
    assert html =~ "August 4, 2026"
    assert html =~ "Course Achievement"
  end

  test "renders the default headline and citation copy" do
    html = Template.render_html(@base_assigns)

    assert html =~ "Certificate of Completion"
    assert html =~ "This is proudly presented to"
    assert html =~ "in recognition of successful completion of the"
  end

  test "allows the headline and citation to be overridden" do
    html =
      Template.render_html(
        Map.merge(@base_assigns, %{
          headline: "Certificate of Recognition",
          citation: "in recognition of excellent participation in the"
        })
      )

    assert html =~ "Certificate of Recognition"
    assert html =~ "in recognition of excellent participation in the"
    refute html =~ "Certificate of Completion"
  end

  test "defaults the issuer to Wasomi Business Institute and derives its seal initials" do
    html = Template.render_html(@base_assigns)

    assert html =~ "Wasomi Business Institute"
    assert html =~ "<div class=\"seal-initials\">WBI</div>"
  end

  test "uses the course's configured issuer name and derives matching initials" do
    html = Template.render_html(Map.put(@base_assigns, :issuer_name, "GS1 Kenya"))

    assert html =~ "GS1 Kenya"
    assert html =~ "<div class=\"seal-initials\">GK</div>"
  end

  test "shows the signatory name in a cursive fallback when no signature image is uploaded" do
    html =
      Template.render_html(
        Map.merge(@base_assigns, %{
          signatory_name: "E. Vance",
          signatory_title: "Country Manager"
        })
      )

    assert html =~ "class=\"signature-name\">E. Vance"
    assert html =~ "Country Manager"
    refute html =~ "class=\"signature-image\""
  end

  test "shows the uploaded signature image instead of the cursive fallback" do
    html =
      Template.render_html(
        Map.merge(@base_assigns, %{
          signatory_name: "E. Vance",
          signatory_title: "Country Manager",
          signature_url: "https://cdn.example.test/signature.png"
        })
      )

    assert html =~
             ~s(<img src="https://cdn.example.test/signature.png" alt="" class="signature-image")

    refute html =~ "class=\"signature-name\""
  end

  test "omits the signature block entirely when no signatory is configured" do
    html = Template.render_html(@base_assigns)

    refute html =~ "Authorized signatory"
    refute html =~ "class=\"signatures\""
  end

  test "renders a second signature block when a second signatory is configured" do
    html =
      Template.render_html(
        Map.merge(@base_assigns, %{
          signatory_name: "E. Vance",
          signatory_title: "Country Manager",
          signatory_two_name: "P. Otieno",
          signatory_two_title: "Chief Executive Officer",
          signatory_two_signature_url: "https://cdn.example.test/ceo.png"
        })
      )

    assert html =~ "P. Otieno"
    assert html =~ "Chief Executive Officer"
    assert html =~ ~s(<img src="https://cdn.example.test/ceo.png" alt="" class="signature-image")
  end

  test "omits the second signature block when only the first signatory is configured" do
    html =
      Template.render_html(
        Map.merge(@base_assigns, %{
          signatory_name: "E. Vance",
          signatory_title: "Country Manager"
        })
      )

    assert html =~ "E. Vance"
    # One signatory block, not two.
    assert html |> String.split("class=\"signatory\"") |> length() == 2
  end

  test "renders the logo when one is supplied and falls back to a wordmark otherwise" do
    with_logo =
      Template.render_html(Map.put(@base_assigns, :logo_data_uri, "data:image/png;base64,QUJD"))

    assert with_logo =~ ~s(<img src="data:image/png;base64,QUJD" alt="" class="logo")
    refute with_logo =~ "class=\"logo-wordmark\""

    without_logo = Template.render_html(@base_assigns)
    assert without_logo =~ "class=\"logo-wordmark\""
  end

  test "renders the contact block only for the branding details supplied" do
    html =
      Template.render_html(
        Map.merge(@base_assigns, %{
          address_lines: ["5th Floor, Nextgen Mall", "Nairobi, Kenya"],
          phone: "+254 700 000 000",
          email: "info@example.test",
          socials: ["Facebook", "LinkedIn"]
        })
      )

    assert html =~ "5th Floor, Nextgen Mall"
    assert html =~ "Nairobi, Kenya"
    assert html =~ "+254 700 000 000"
    assert html =~ "info@example.test"
    assert html =~ "Facebook | LinkedIn"
  end

  test "omits the contact and socials blocks when no branding details are supplied" do
    html = Template.render_html(@base_assigns)

    refute html =~ "class=\"contact-group\""
    refute html =~ "class=\"contact-socials\""
  end

  test "draws a placeholder QR by default and a real one when a data URI is supplied" do
    placeholder = Template.render_html(@base_assigns)
    assert placeholder =~ "class=\"qr-placeholder\""
    refute placeholder =~ "class=\"qr\""

    real =
      Template.render_html(Map.put(@base_assigns, :qr_data_uri, "data:image/png;base64,QUJD"))

    assert real =~ ~s(<img src="data:image/png;base64,QUJD" alt="" class="qr")
    refute real =~ "class=\"qr-placeholder\""
  end
end
