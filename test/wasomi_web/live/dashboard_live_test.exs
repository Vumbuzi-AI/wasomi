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

  test "shows only active courses and links to the protected player", %{conn: conn, user: user} do
    active_course = course_fixture(status: :published, title: "Active course")
    active_module = course_module_fixture(course_id: active_course.id, position: 1)
    lecture = lecture_fixture(module_id: active_module.id, position: 1, title: "First lesson")
    enrollment_fixture(user_id: user.id, course_id: active_course.id, status: :active)

    pending_course = course_fixture(status: :published, title: "Pending course")
    enrollment_fixture(user_id: user.id, course_id: pending_course.id, status: :pending)

    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ active_course.title
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
    assert html =~ "KES 1,250"
    refute html =~ "1,250.00"
    refute html =~ "KBI-RECEIPT-PENDING"
  end

  defp admin_fixture(attrs \\ %{}) do
    user = Wasomi.AccountsFixtures.user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end

  test "a live-connected dashboard shows an admin grant the moment it's broadcast", %{
    conn: conn,
    user: user
  } do
    admin = admin_fixture()
    course = course_fixture(status: :published, title: "Granted course")

    {:ok, view, html} = live(conn, ~p"/dashboard")
    refute html =~ "Granted course"
    refute has_element?(view, "#dashboard-notifications")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    assert has_element?(view, "#dashboard-notifications", "Course access granted")
    assert has_element?(view, "#dashboard-notifications", "Granted course")
    assert has_element?(view, "#dashboard-course-#{course.id}")
  end

  test "dismissing an in-app notification marks it read and removes it from the panel", %{
    conn: conn,
    user: user
  } do
    admin = admin_fixture()
    course = course_fixture(status: :published, title: "Granted course")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    {:ok, view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Course access granted"

    [notification] = Wasomi.Notifications.list_unread_for_user(user)

    html =
      view
      |> element("#notification-#{notification.id} button", "Dismiss")
      |> render_click()

    refute html =~ "Course access granted"
    assert Wasomi.Notifications.list_unread_for_user(user) == []
  end

  test "cannot dismiss another learner's notification", %{conn: conn} do
    admin = admin_fixture()
    other_learner = Wasomi.AccountsFixtures.user_fixture()
    course = course_fixture(status: :published, title: "Someone else's course")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(other_learner, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    [other_notification] = Wasomi.Notifications.list_unread_for_user(other_learner)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    render_click(view, "dismiss_notification", %{"id" => other_notification.id})

    assert Wasomi.Notifications.list_unread_for_user(other_learner) != []
  end
end
