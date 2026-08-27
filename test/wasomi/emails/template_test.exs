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

  describe "rich/1" do
    test "wraps a :bold segment in <strong>, escaping its content" do
      assert Template.rich(["Hi ", {:bold, "Jane"}, "!"]) ==
               {:safe, "Hi <strong>Jane</strong>!", "Hi Jane!"}
    end

    test "escapes a plain (non-bold) segment the same as any other body text" do
      assert {:safe, html, plain} = Template.rich([{:bold, "<script>"}, " & friends"])
      assert html == "<strong>&lt;script&gt;</strong> &amp; friends"
      assert plain == "<script> & friends"
    end

    test "render/1 emits a rich intro/body paragraph's HTML unescaped, but as the safe markup rich/1 built" do
      html =
        Template.render(%{
          title: "Welcome",
          intro: Template.rich(["Hi ", {:bold, "Jane"}, ","]),
          body: [Template.rich(["Enrolled in ", {:bold, "GS1 Basics"}, "."])]
        })

      assert html =~ "Hi <strong>Jane</strong>,"
      assert html =~ "Enrolled in <strong>GS1 Basics</strong>."
    end

    test "render_text/1 renders a rich paragraph as plain text, with no <strong> tags" do
      text =
        Template.render_text(%{
          title: "Welcome",
          intro: Template.rich(["Hi ", {:bold, "Jane"}, ","])
        })

      assert text =~ "Hi Jane,"
      refute text =~ "<strong>"
    end
  end

  describe "logo" do
    test "render/1 inlines the real logo as a data URI, not the old placeholder mark" do
      html = Template.render(%{title: "Welcome"})

      assert html =~ ~s(<img src="data:image/png;base64,)
      assert html =~ ~s(alt="Wasomi")
    end
  end

  describe "brand color" do
    test "the CTA button uses the brand orange, not a neutral dark" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Go", url: "https://wasomi.com"}
        })

      assert html =~ "background-color:#f97316"
    end
  end
end
