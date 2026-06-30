defmodule WasomiWeb.HomeLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  alias Wasomi.Accounts

  test "renders published backend courses on the homepage", %{conn: conn} do
    published = course_fixture(status: :published, title: "Backend Course")
    _draft = course_fixture(status: :draft, title: "Hidden Draft")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ published.title
    refute html =~ "Hidden Draft"
  end

  test "shows a learner dashboard button for logged-in learners", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "My dashboard"
    assert html =~ ~s|href="/dashboard"|
  end

  test "shows an admin dashboard button for logged-in administrators", %{conn: conn} do
    {:ok, admin} = user_fixture() |> Accounts.update_user_role(:admin)
    conn = log_in_user(conn, admin)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Admin dashboard"
    assert html =~ ~s|href="/admin"|
  end
end
