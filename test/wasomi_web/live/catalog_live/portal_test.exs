defmodule WasomiWeb.CatalogLive.PortalTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.{AccountsFixtures, CatalogFixtures, EnrollmentsFixtures}

  test "redirects an anonymous visitor to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/catalog")
  end

  test "keeps the public catalog available to anonymous visitors with no portal chrome", %{
    conn: conn
  } do
    course = course_fixture(status: :published, title: "Public Course")

    {:ok, _view, html} = live(conn, ~p"/courses")

    assert html =~ course.title
    refute html =~ "student-sidebar"
    refute html =~ "Explore all GS1 courses."
  end

  test "renders the learner sidebar and published courses for an authenticated learner", %{
    conn: conn
  } do
    user = user_fixture()
    course = course_fixture(status: :published, title: "Portal Catalog Course")
    _draft = course_fixture(status: :draft, title: "Hidden Draft Course")

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/catalog")

    assert html =~ "student-sidebar"
    assert html =~ "Explore all GS1 courses."
    assert html =~ course.title
    refute html =~ "Hidden Draft Course"
  end

  test "shows an unenrolled course with a link to its public detail page", %{conn: conn} do
    user = user_fixture()
    course = course_fixture(status: :published, title: "Not Yet Enrolled")

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/catalog")

    assert html =~ course.title
    assert html =~ ~s(href="/courses/#{course.slug}")
  end

  test "shows an enrolled course with an Enrolled badge and a link into the course player", %{
    conn: conn
  } do
    user = user_fixture()
    course = course_fixture(status: :published, title: "Already Enrolled")
    course_module = course_module_fixture(course_id: course.id, position: 1)
    lecture_fixture(module_id: course_module.id, position: 1)

    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/catalog")

    assert html =~ course.title
    assert html =~ "Enrolled"
    assert html =~ ~s(href="/learn/courses/#{course.slug}")
  end

  test "distinguishes enrolled from unenrolled courses on the same page", %{conn: conn} do
    user = user_fixture()
    enrolled = course_fixture(status: :published, title: "Enrolled Course")
    enrolled_module = course_module_fixture(course_id: enrolled.id, position: 1)
    lecture_fixture(module_id: enrolled_module.id, position: 1)
    available = course_fixture(status: :published, title: "Available Course")

    enrollment_fixture(user_id: user.id, course_id: enrolled.id, status: :active)

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/catalog")

    assert html =~ ~s(href="/learn/courses/#{enrolled.slug}")
    assert html =~ ~s(href="/courses/#{available.slug}")
  end

  test "the price filter narrows the catalog to free or paid courses", %{conn: conn} do
    user = user_fixture()

    free =
      course_fixture(status: :published, title: "Free Course", is_free: true, price_minor: nil)

    paid =
      course_fixture(status: :published, title: "Paid Course", is_free: false, price_minor: 5000)

    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, ~p"/catalog?price=free")
    assert html =~ free.title
    refute html =~ paid.title

    {:ok, _view, html} = live(conn, ~p"/catalog?price=paid")
    assert html =~ paid.title
    refute html =~ free.title
  end

  test "hide_enrolled removes courses the learner already has access to", %{conn: conn} do
    user = user_fixture()
    enrolled = course_fixture(status: :published, title: "Owned Course")
    available = course_fixture(status: :published, title: "Fresh Course")
    enrollment_fixture(user_id: user.id, course_id: enrolled.id, status: :active)

    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, ~p"/catalog")
    assert html =~ enrolled.title
    assert html =~ available.title

    {:ok, _view, html} = live(conn, ~p"/catalog?hide_enrolled=1")
    refute html =~ enrolled.title
    assert html =~ available.title
  end

  test "a pending (unpaid) enrollment is treated as not yet enrolled", %{conn: conn} do
    user = user_fixture()
    course = course_fixture(status: :published, title: "Pending Payment Course")

    enrollment_fixture(user_id: user.id, course_id: course.id, status: :pending)

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/catalog")

    assert html =~ ~s(href="/courses/#{course.slug}")
    refute html =~ ~s(href="/learn/courses/#{course.slug}")
  end

  test "search filters the catalog via a patch, keeping the learner on the portal route", %{
    conn: conn
  } do
    user = user_fixture()
    _match = course_fixture(status: :published, title: "GS1 Fundamentals")
    _other = course_fixture(status: :published, title: "Traceability Basics")

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/catalog")

    html =
      view
      |> form("form", %{search: "GS1"})
      |> render_change()

    assert html =~ "GS1 Fundamentals"
    refute html =~ "Traceability Basics"
    assert_patch(view, ~p"/catalog?search=GS1")
  end
end
