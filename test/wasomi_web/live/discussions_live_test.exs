defmodule WasomiWeb.DiscussionsLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Channels

  setup :register_and_log_in_user

  defp published_course(title) do
    course = course_fixture(status: :published, title: title)
    module = course_module_fixture(course_id: course.id)
    lecture_fixture(module_id: module.id)
    Wasomi.Catalog.get_course_by_slug!(course.slug)
  end

  test "lists only the channels the learner belongs to", %{conn: conn, user: user} do
    mine = published_course("Data Foundations")
    _theirs = published_course("Someone Else's Course")
    enrollment_fixture(user_id: user.id, course_id: mine.id, status: :active)

    {:ok, _view, html} = live(conn, ~p"/discussions")

    assert html =~ "Data Foundations"
    refute html =~ "Someone Else&#39;s Course"
  end

  test "empty state when the learner has no channels", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/discussions")
    assert html =~ "not in any course channels yet"
  end

  test "opening a course renders its channel and clears its unread", %{conn: conn, user: user} do
    course = published_course("Applied Negotiation")
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

    {:ok, admin} = user_fixture() |> Wasomi.Accounts.update_user_role(:admin)
    chan = Channels.get_or_create_for_course(course)
    {:ok, _} = Channels.post_message(admin, chan, "welcome everyone")

    {:ok, view, _html} = live(conn, ~p"/discussions")
    assert has_element?(view, "span.bg-primary", "1")

    view |> element("a", "Applied Negotiation") |> render_click()

    child = find_live_child(view, "learner-channel-#{course.slug}")
    assert render(child) =~ "welcome everyone"
    assert has_element?(child, "#course-channel-composer")
    refute has_element?(view, "span.bg-primary", "1")
  end
end
