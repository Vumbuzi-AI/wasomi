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
    # anon CTA is action-first and routes through the auth wall to checkout
    assert html =~ "Enroll &amp; Pay"
    assert html =~ ~s(href="/courses/#{course.slug}/checkout")
    refute html =~ "Create account"

    # following that CTA bounces an anon visitor to sign in, with the
    # checkout path remembered for after they authenticate
    assert {:error, {:redirect, %{to: "/users/log_in"}}} =
             live(conn, ~p"/courses/#{course.slug}/checkout")
  end

  test "renders a local thumbnail as an absolute social image URL", %{conn: conn} do
    course =
      course_fixture(
        status: :published,
        thumbnail_key: "/uploads/thumbnails/course-cover.png"
      )

    {:ok, _view, html} = live(conn, ~p"/courses/#{course.slug}")

    assert html =~
             ~s(content="#{WasomiWeb.Endpoint.url()}/uploads/thumbnails/course-cover.png")
  end

  test "renders a document-only lecture without a video duration", %{conn: conn} do
    course = course_fixture(status: :published)
    course_module = course_module_fixture(course_id: course.id, position: 1)

    lecture =
      lecture_fixture(
        module_id: course_module.id,
        position: 1,
        title: "Document-only lecture",
        video_provider: nil,
        video_asset_id: nil,
        duration_seconds: nil
      )

    {:ok, _view, html} = live(conn, ~p"/courses/#{course.slug}")

    assert html =~ lecture.title
    assert html =~ "0 min"
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

  test "the public catalog price filter narrows to free or paid courses", %{conn: conn} do
    free = course_fixture(status: :published, title: "Zero Cost", is_free: true, price_minor: nil)

    paid =
      course_fixture(status: :published, title: "Premium", is_free: false, price_minor: 9000)

    {:ok, _view, html} = live(conn, ~p"/courses?price=free")
    assert html =~ free.title
    refute html =~ paid.title

    {:ok, _view, html} = live(conn, ~p"/courses?price=paid")
    assert html =~ paid.title
    refute html =~ free.title
  end

  describe "course detail shell" do
    test "an anonymous visitor gets the public marketing header", %{conn: conn} do
      course = course_fixture(status: :published, title: "Public Storefront")

      {:ok, _view, html} = live(conn, ~p"/courses/#{course.slug}")

      assert html =~ ~s(id="nav-toggle")
      refute html =~ ~s(id="student-sidebar")
    end

    test "a signed-in learner gets the learner sidebar shell", %{conn: conn} do
      course = course_fixture(status: :published, title: "In-App View")
      conn = log_in_user(conn, Wasomi.AccountsFixtures.user_fixture())

      {:ok, _view, html} = live(conn, ~p"/courses/#{course.slug}")

      assert html =~ ~s(id="student-sidebar")
      refute html =~ ~s(id="nav-toggle")
      assert html =~ course.title
      assert html =~ "Back to all courses"
      # the back link stays inside the authenticated portal, not the public catalog
      assert html =~ ~s(href="/catalog")
      refute html =~ ~s(href="/courses")
    end
  end
end
