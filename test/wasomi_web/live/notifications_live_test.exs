defmodule WasomiWeb.NotificationsLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures

  setup :register_and_log_in_user

  test "requires authentication" do
    conn = Plug.Test.init_test_session(build_conn(), %{})

    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/notifications")
  end

  test "shows an empty state when the learner has no notifications", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/notifications")

    assert html =~ "Notifications"
    assert has_element?(view, "#notifications-empty", "Nothing to catch up on.")
  end

  test "shows unread and read notification history newest first", %{conn: conn, user: user} do
    admin = admin_fixture()
    older_course = course_fixture(status: :published, title: "Older inbox course")
    newer_course = course_fixture(status: :published, title: "Newer inbox course")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => older_course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => newer_course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    [newer_notification, older_notification] = Wasomi.Notifications.list_for_user(user)
    {:ok, _notification} = Wasomi.Notifications.mark_read(older_notification)

    {:ok, view, html} = live(conn, ~p"/notifications")

    assert html =~ "1 unread"
    assert html =~ "Newer inbox course"
    assert html =~ "Older inbox course"
    assert html =~ "Unread"
    assert html =~ "Read"
    assert has_element?(view, "#notification-#{newer_notification.id} button", "Dismiss")
    refute has_element?(view, "#notification-#{older_notification.id} button", "Dismiss")
  end

  test "shows the learner sidebar unread indicator for visible unread notifications", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published, title: "Indicator course")
    {:ok, enrollment} = Wasomi.Enrollments.create_pending_enrollment(user, course)

    assert {:ok, _notification} = Wasomi.Notifications.deliver_reengagement_gone_quiet(enrollment)

    {:ok, view, _html} = live(conn, ~p"/notifications")

    assert has_element?(view, "#student-nav-notifications .sidebar-notification-dot")
    assert has_element?(view, "#student-nav-notifications .sidebar-notification-count", "1")
  end

  test "does not show ready-to-start reengagement nudges in the platform inbox", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published, title: "Email-only starter")
    {:ok, enrollment} = Wasomi.Enrollments.create_pending_enrollment(user, course)

    assert {:ok, _notification} =
             Wasomi.Notifications.deliver_reengagement_never_started(enrollment)

    {:ok, view, html} = live(conn, ~p"/notifications")

    assert has_element?(view, "#notifications-empty")
    refute has_element?(view, "#student-nav-notifications .sidebar-notification-dot")
    refute has_element?(view, "#student-nav-notifications .sidebar-notification-count")
    refute html =~ "Ready to start"
    refute html =~ "Email-only starter"
  end

  test "dismissing a notification marks it read without hiding it from history", %{
    conn: conn,
    user: user
  } do
    admin = admin_fixture()
    course = course_fixture(status: :published, title: "Dismissible inbox course")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    [notification] = Wasomi.Notifications.list_for_user(user)

    {:ok, view, _html} = live(conn, ~p"/notifications")

    html =
      view
      |> element("#notification-#{notification.id} button", "Dismiss")
      |> render_click()

    assert html =~ "0 unread"
    assert html =~ "Dismissible inbox course"
    assert html =~ "Read"
    refute has_element?(view, "#notification-#{notification.id} button", "Dismiss")
    refute has_element?(view, "#student-nav-notifications .sidebar-notification-dot")
    refute has_element?(view, "#student-nav-notifications .sidebar-notification-count")
    assert [%{read_at: %DateTime{}}] = Wasomi.Notifications.list_for_user(user)
  end

  test "clicking a course-scoped notification's CTA marks it read and lands on that course", %{
    conn: conn,
    user: user
  } do
    admin = admin_fixture()
    course = course_fixture(status: :published, title: "Linked course")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    [notification] = Wasomi.Notifications.list_for_user(user)

    {:ok, view, _html} = live(conn, ~p"/notifications")

    assert has_element?(view, "#notification-#{notification.id} button", "Go to course")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#notification-#{notification.id} button", "Go to course")
             |> render_click()

    assert to == ~p"/learn/courses/#{course.slug}"
    assert [%{read_at: %DateTime{}}] = Wasomi.Notifications.list_for_user(user)
  end

  test "a channel-mention CTA deep-links a learner to the message", %{conn: conn, user: user} do
    admin = admin_fixture()
    course = course_fixture(status: :published, title: "Mentioned course")
    module = course_module_fixture(course_id: course.id)
    lecture_fixture(module_id: module.id)
    course = Wasomi.Catalog.get_course_by_slug!(course.slug)

    {:ok, _} =
      Wasomi.Enrollments.grant_access(user, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    chan = Wasomi.Channels.get_or_create_for_course(course)

    {:ok, message} =
      Wasomi.Channels.post_message(admin, chan, "hi @[#{user.name}](user:#{user.id})")

    [notification | _] =
      Wasomi.Notifications.list_for_user(user)
      |> Enum.filter(&(&1.kind == :channel_mention))

    {:ok, view, _html} = live(conn, ~p"/notifications")

    assert has_element?(view, "#notification-#{notification.id} button", "Open discussion")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#notification-#{notification.id} button", "Open discussion")
             |> render_click()

    assert to == ~p"/learn/courses/#{course.slug}?#{%{tab: "discussion", msg: message.id}}"
  end

  test "a channel-mention CTA sends an admin to the preview player", %{conn: conn} do
    admin = admin_fixture(%{name: "Wasomi Admin"})
    other = Wasomi.AccountsFixtures.user_fixture(%{name: "One Student"})
    course = course_fixture(status: :published, title: "Admin mention course")
    module = course_module_fixture(course_id: course.id)
    lecture_fixture(module_id: module.id)
    course = Wasomi.Catalog.get_course_by_slug!(course.slug)
    admin2 = admin_fixture()

    {:ok, _} =
      Wasomi.Enrollments.grant_access(other, admin2, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    chan = Wasomi.Channels.get_or_create_for_course(course)

    {:ok, message} =
      Wasomi.Channels.post_message(other, chan, "ping @[Wasomi Admin](user:#{admin.id})")

    [notification | _] =
      Wasomi.Notifications.list_for_user(admin)
      |> Enum.filter(&(&1.kind == :channel_mention))

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/notifications")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#notification-#{notification.id} button", "Open discussion")
             |> render_click()

    assert to ==
             ~p"/admin/discussions?#{%{course: course.slug, msg: message.id}}"
  end

  test "cannot dismiss another learner's notification", %{conn: conn} do
    admin = admin_fixture()
    other_learner = Wasomi.AccountsFixtures.user_fixture()
    course = course_fixture(status: :published, title: "Private inbox course")

    {:ok, _enrollment} =
      Wasomi.Enrollments.grant_access(other_learner, admin, %{
        "course_id" => course.id,
        "reason" => "Manual enrollment for a partner scholarship"
      })

    [other_notification] = Wasomi.Notifications.list_for_user(other_learner)

    {:ok, view, _html} = live(conn, ~p"/notifications")

    render_click(view, "dismiss_notification", %{"id" => other_notification.id})

    assert [%{read_at: nil}] = Wasomi.Notifications.list_for_user(other_learner)
  end

  defp admin_fixture(attrs \\ %{}) do
    user = Wasomi.AccountsFixtures.user_fixture(attrs)
    {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
    admin
  end
end
