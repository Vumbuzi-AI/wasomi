defmodule WasomiWeb.DashboardLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.Learning

  setup :register_and_log_in_user

  test "requires authentication", %{} do
    conn = Plug.Test.init_test_session(build_conn(), %{})

    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/dashboard")
  end

  test "shows first-use copy for a new learner with no profile or courses", %{
    conn: conn,
    user: user
  } do
    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Welcome to Wasomi, #{String.split(user.name) |> List.first()}."
    assert html =~ "Complete profile"
    assert has_element?(view, "a[href='/users/settings']", "Complete profile")
    refute html =~ "Welcome back"
  end

  test "a first-time learner sees courses to start, not empty progress metrics", %{
    conn: conn,
    user: user
  } do
    {:ok, _user} = Wasomi.Accounts.update_user_profile(user, %{occupation: "Operations analyst"})
    published = course_fixture(status: :published, title: "Intro to GS1")

    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Ready when you are"
    assert html =~ "Choose a course to begin"
    assert has_element?(view, "#dashboard-starter a[href='/courses/#{published.slug}']")
    # A path to the full catalog so the starter list doesn't look exhaustive.
    assert has_element?(view, "#dashboard-starter a[href='/catalog']", "Browse all courses")
    # No zero-value progress cards, no "continue" section for a brand-new learner.
    refute has_element?(view, "#dashboard-stats")
    refute has_element?(view, "#dashboard-receipts")
    refute html =~ "Pick up where you left off"
    refute html =~ "Welcome back"
  end

  test "offers an opt-in tour prompt that goes away once answered", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/dashboard")
    assert html =~ "show you around"
    assert has_element?(view, "#product-tour", "Show me around")

    view |> element("button", "I'll find my way") |> render_click()

    refute has_element?(view, "#product-tour")
    refute render(view) =~ "show you around"
    assert Wasomi.Accounts.tour_completed?(Wasomi.Accounts.get_user!(user.id))
  end

  test "offers the full catalog when more starter courses exist than are shown", %{conn: conn} do
    for n <- 1..7, do: course_fixture(status: :published, title: "Starter #{n}", position: n)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard-starter", "Starter 1")
    refute has_element?(view, "#dashboard-starter", "Starter 7")
    assert has_element?(view, "#dashboard-starter a[href='/catalog']", "View the full catalog")
  end

  test "shows only active courses and links to the protected player", %{conn: conn, user: user} do
    active_course = course_fixture(status: :published, title: "Active course")
    active_module = course_module_fixture(course_id: active_course.id, position: 1)
    lecture = lecture_fixture(module_id: active_module.id, position: 1, title: "First lesson")
    enrollment_fixture(user_id: user.id, course_id: active_course.id, status: :active)

    pending_course = course_fixture(status: :published, title: "Pending course")
    enrollment_fixture(user_id: user.id, course_id: pending_course.id, status: :pending)

    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ active_course.title
    assert html =~ "Your first course is ready"
    assert html =~ "Start learning"
    assert html =~ lecture.title
    refute html =~ pending_course.title
    assert has_element?(view, "#dashboard-course-#{active_course.id}")

    assert has_element?(
             view,
             "#dashboard-course-#{active_course.id} a[href='/learn/courses/#{active_course.slug}']",
             "Start course"
           )
  end

  test "renders current progress and a continue-watching action", %{conn: conn, user: user} do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)

    first =
      lecture_fixture(
        module_id: module.id,
        position: 1,
        duration_seconds: 100,
        title: "First lesson"
      )

    lecture_fixture(module_id: module.id, position: 2, duration_seconds: 100)
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

    course = Wasomi.Catalog.get_course_by_slug!(course.slug)
    assert {:ok, _, _events} = Learning.record_progress(user, first, 40)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert render(view) =~ "Welcome back"
    assert has_element?(view, "#course-progress-#{course.id}", "0%")
    assert has_element?(view, "#dashboard-course-#{course.id}", "First lesson")
    assert has_element?(view, "#dashboard-course-#{course.id}", "Continue learning")
  end

  test "shows successful payment receipts but not pending or failed attempts", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published, title: "Receipt course")
    enrollment = enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

    successful =
      payment_fixture(
        user_id: user.id,
        course_id: course.id,
        enrollment_id: enrollment.id,
        amount_minor: 125_000,
        currency: "KES",
        provider_reference: "KBI-RECEIPT-PAID",
        status: :successful
      )

    pending =
      payment_fixture(
        user_id: user.id,
        course_id: course.id,
        enrollment_id: enrollment.id,
        provider_reference: "KBI-RECEIPT-PENDING",
        status: :pending
      )

    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#payment-receipt-#{successful.id}")
    refute has_element?(view, "#payment-receipt-#{pending.id}")
    assert html =~ "KBI-RECEIPT-PAID"
    assert html =~ "KES"
    refute html =~ "KBI-RECEIPT-PENDING"
  end

  defp admin_fixture(attrs \\ %{}) do
    user = Wasomi.AccountsFixtures.user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  test "a live-connected dashboard updates learning content and sidebar indicator on admin grant",
       %{
         conn: conn,
         user: user
       } do
    admin = admin_fixture()
    course = course_fixture(status: :published, title: "Granted course")

    {:ok, view, _html} = live(conn, ~p"/dashboard")
    refute has_element?(view, "#dashboard-course-#{course.id}")
    refute has_element?(view, "#dashboard-notifications")
    refute has_element?(view, "#student-nav-notifications .sidebar-notification-dot")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    refute has_element?(view, "#dashboard-notifications")
    assert has_element?(view, "#dashboard-course-#{course.id}")
    assert has_element?(view, "#student-nav-notifications .sidebar-notification-dot")
  end
end
