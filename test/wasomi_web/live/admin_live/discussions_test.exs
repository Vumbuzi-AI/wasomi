defmodule WasomiWeb.AdminLive.DiscussionsTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Channels

  defp admin_conn(conn) do
    {:ok, admin} = user_fixture() |> Wasomi.Accounts.update_user_role(:admin)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  setup %{conn: conn}, do: admin_conn(conn)

  defp published_course(title) do
    course = course_fixture(status: :published, title: title)
    module = course_module_fixture(course_id: course.id)
    lecture_fixture(module_id: module.id)
    Wasomi.Catalog.get_course_by_slug!(course.slug)
  end

  test "lists course channels with stats and unread", %{conn: conn} do
    quiet = published_course("Quiet Course")
    busy = published_course("Busy Course")
    learner = user_fixture(%{name: "Amara"})
    enrollment_fixture(user_id: learner.id, course_id: busy.id, status: :active)

    {:ok, _} =
      Channels.post_message(learner, Channels.get_or_create_for_course(busy), "hello team")

    {:ok, view, html} = live(conn, ~p"/admin/discussions")

    assert html =~ "Quiet Course"
    assert html =~ "Busy Course"
    assert html =~ "1 message"
    # the busy channel shows an unread badge for the admin
    assert has_element?(view, "a", "Busy Course")
    assert has_element?(view, "span.bg-primary", "1")
    refute has_element?(view, ~s([id="admin-channel-#{quiet.slug}"]))
  end

  test "selecting a course renders its channel panel", %{conn: conn} do
    course = published_course("Applied Negotiation")

    {:ok, view, _html} = live(conn, ~p"/admin/discussions")

    view
    |> element("a", "Applied Negotiation")
    |> render_click()

    assert has_element?(view, ~s([id="admin-channel-#{course.slug}"]))
    child = find_live_child(view, "admin-channel-#{course.slug}")
    assert render(child) =~ "Cohort discussion"
    assert has_element?(child, "#course-channel-composer")
  end

  test "search filters the course list", %{conn: conn} do
    published_course("Data Foundations")
    published_course("Retail Analytics")

    {:ok, view, _html} = live(conn, ~p"/admin/discussions")

    view |> form("form[phx-change='search']", %{q: "retail"}) |> render_change()

    html = render(view)
    assert html =~ "Retail Analytics"
    refute html =~ "Data Foundations"
  end
end
