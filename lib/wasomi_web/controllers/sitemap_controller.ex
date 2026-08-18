defmodule WasomiWeb.SitemapController do
  use WasomiWeb, :controller

  alias Wasomi.Catalog

  def index(conn, _params) do
    urls =
      [url(~p"/"), url(~p"/courses")] ++
        Enum.map(Catalog.list_published_courses(), fn course ->
          url(~p"/courses/#{course.slug}")
        end)

    body =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
        ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
        Enum.map(urls, fn location ->
          ["  <url><loc>", escape_xml(location), "</loc></url>\n"]
        end),
        "</urlset>\n"
      ]

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(:ok, body)
  end

  defp escape_xml(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
