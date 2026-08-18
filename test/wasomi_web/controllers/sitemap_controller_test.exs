defmodule WasomiWeb.SitemapControllerTest do
  use WasomiWeb.ConnCase

  import Wasomi.CatalogFixtures

  test "lists public pages and published courses only", %{conn: conn} do
    published = course_fixture(status: :published)
    draft = course_fixture(status: :draft)

    conn = get(conn, ~p"/sitemap.xml")

    assert response_content_type(conn, :xml) =~ "application/xml"
    assert response(conn, 200) =~ url(~p"/courses/#{published.slug}")
    refute response(conn, 200) =~ url(~p"/courses/#{draft.slug}")
  end
end
