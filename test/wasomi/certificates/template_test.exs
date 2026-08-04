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

  test "defaults the issuer to Wasomi Business Institute and derives its watermark initials" do
    html = Template.render_html(@base_assigns)

    assert html =~ "Wasomi Business Institute"
    assert html =~ "<div class=\"watermark\">WBI</div>"
  end

  test "uses the course's configured issuer name and derives matching initials" do
    html = Template.render_html(Map.put(@base_assigns, :issuer_name, "GS1 Kenya"))

    assert html =~ "GS1 Kenya"
    assert html =~ "<div class=\"watermark\">GK</div>"
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
    refute html =~ "<img"
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

  test "omits the signatory footer block entirely when no signatory is configured" do
    html = Template.render_html(@base_assigns)

    refute html =~ "Authorized signatory"
  end
end
