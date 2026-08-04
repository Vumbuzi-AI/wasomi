defmodule Wasomi.Emails.TemplateTest do
  use ExUnit.Case, async: true

  alias Wasomi.Emails.Template

  describe "render/1 HTML template CTA safety" do
    test "renders CTA button for valid https URL" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Go to Dashboard", url: "https://wasomi.com/dashboard"}
        })

      assert html =~ ~s(href="https://wasomi.com/dashboard")
      assert html =~ "Go to Dashboard"
    end

    test "renders CTA button for valid http URL" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Local Dev", url: "http://localhost:4000/dashboard"}
        })

      assert html =~ ~s(href="http://localhost:4000/dashboard")
      assert html =~ "Local Dev"
    end

    test "renders CTA button for valid relative URL" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Relative Link", url: "/dashboard"}
        })

      assert html =~ ~s(href="/dashboard")
      assert html =~ "Relative Link"
    end

    test "omits CTA button for unsafe javascript: scheme" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Click Me", url: "javascript:alert(1)"}
        })

      refute html =~ "javascript:"
      refute html =~ "Click Me"
    end

    test "omits CTA button for unsafe data: scheme" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Data URI", url: "data:text/html,<script>alert(1)</script>"}
        })

      refute html =~ "data:text"
      refute html =~ "Data URI"
    end

    test "omits CTA button for protocol-relative // URLs" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "External Unsafe", url: "//evil.com/phish"}
        })

      refute html =~ "//evil.com/phish"
      refute html =~ "External Unsafe"
    end

    test "renders CTA button for the test-harness [TOKEN]...[TOKEN] placeholder" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Confirm", url: "[TOKEN]abc123[TOKEN]"}
        })

      assert html =~ ~s(href="[TOKEN]abc123[TOKEN]")
      assert html =~ "Confirm"
    end

    test "omits CTA button for a bare hostname without a scheme" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Bare Host", url: "evil.com/phish"}
        })

      refute html =~ ~s(href="evil.com/phish")
      refute html =~ "Bare Host"
    end

    test "omits CTA button for a bare hostname that merely contains [TOKEN]" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Bare Host Token", url: "evil.com/[TOKEN]/phish"}
        })

      refute html =~ ~s(href="evil.com)
      refute html =~ "Bare Host Token"
    end
  end

  describe "render_text/1 plain text CTA safety" do
    test "includes CTA link for safe URL" do
      text =
        Template.render_text(%{
          title: "Welcome",
          cta: %{label: "Go to Dashboard", url: "https://wasomi.com/dashboard"}
        })

      assert text =~ "Go to Dashboard: https://wasomi.com/dashboard"
    end

    test "omits CTA link for unsafe URL scheme" do
      text =
        Template.render_text(%{
          title: "Welcome",
          cta: %{label: "Click Me", url: "javascript:alert(1)"}
        })

      refute text =~ "javascript:"
      refute text =~ "Click Me"
    end
  end
end
