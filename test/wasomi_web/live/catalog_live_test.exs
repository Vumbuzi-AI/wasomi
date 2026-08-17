defmodule WasomiWeb.CatalogLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures

  test "lists published courses and hides drafts", %{conn: conn} do
    published = course_fixture(status: :published, title: "Published Course")
    _draft = course_fixture(status: :draft, title: "Draft Course")

    {:ok, _view, html} = live(conn, ~p"/courses")

    assert html =~ published.title
    refute html =~ "Draft Course"
  end

  test "shows an ordered public curriculum without video asset identifiers", %{conn: conn} do
    course = course_fixture(status: :published, title: "The Human Stack")
    course_module = course_module_fixture(course_id: course.id, position: 1)

    lecture =
      lecture_fixture(
        module_id: course_module.id,
        position: 1,
        title: "Why communication matters",
        video_asset_id: "secret-provider-asset"
      )

    {:ok, _view, html} = live(conn, ~p"/courses/#{course.slug}")

    assert html =~ course.title
    assert html =~ course_module.title
    assert html =~ lecture.title
    refute html =~ lecture.video_asset_id
    assert html =~ "Create account"
  end

  test "displays Free and Enroll for Free on catalog course show for logged in user", %{
    conn: conn
  } do
    user = Wasomi.AccountsFixtures.user_fixture()

    free_course =
      course_fixture(
        status: :published,
        title: "Free Course",
        is_free: true,
        price_minor: nil
      )

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/courses/#{free_course.slug}")

    assert html =~ "Free"
    assert html =~ "Enroll for Free"
  end
end
