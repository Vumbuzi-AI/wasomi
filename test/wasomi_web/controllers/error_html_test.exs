defmodule WasomiWeb.ErrorHTMLTest do
  use WasomiWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    html = render_to_string(WasomiWeb.ErrorHTML, "404", "html", [])
    assert html =~ "We can&#39;t find that page"
  end

  test "renders 403.html" do
    html = render_to_string(WasomiWeb.ErrorHTML, "403", "html", [])
    assert html =~ "don&#39;t have access"
  end

  test "renders 500.html" do
    html = render_to_string(WasomiWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Something went wrong on our end"
  end

  test "falls back to the branded generic card for a status without a dedicated template" do
    html = render_to_string(WasomiWeb.ErrorHTML, "422", "html", [])
    assert html =~ "422"
    assert html =~ "Unprocessable Content"
    assert html =~ "Go to homepage"
  end

  test "still falls back to plain text for a template with no numeric status" do
    assert render_to_string(WasomiWeb.ErrorHTML, "not-a-status", "html", []) ==
             "Internal Server Error"
  end
end
