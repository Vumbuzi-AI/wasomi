defmodule WasomiWeb.HomeLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  alias Wasomi.Accounts

  test "renders published backend courses on the homepage", %{conn: conn} do
    published = course_fixture(status: :published, title: "Backend Course")
    _draft = course_fixture(status: :draft, title: "Hidden Draft")
    _internal = course_fixture(status: :published, title: "Hidden Internal", is_internal: true)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ published.title
    refute html =~ "Hidden Draft"
    refute html =~ "Hidden Internal"
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

  test "mounts the Zebra chat embed on the homepage but not the learner dashboard", %{conn: conn} do
    {:ok, _view, home} = live(conn, ~p"/")
    assert home =~ ~s|id="zebra-chat-embed"|
    assert home =~ ~s|phx-hook="ZebraChat"|

    {:ok, _view, dashboard} = conn |> log_in_user(user_fixture()) |> live(~p"/dashboard")
    refute dashboard =~ "ZebraChat"
  end
end
