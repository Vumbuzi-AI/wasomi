defmodule WasomiWeb.AdminLive.NotificationsTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.PaymentsFixtures

  alias Wasomi.{Accounts, Notifications}

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Accounts.update_user_role(user, :admin)
    admin
  end

  defp seed_payment_notice(student_name, course_title) do
    student = user_fixture(%{name: student_name})
    course = course_fixture(status: :published, title: course_title)

    payment =
      payment_fixture(%{
        user_id: student.id,
        course_id: course.id,
        status: :successful,
        amount_minor: 5_000
      })

    :ok = Notifications.deliver_student_payment_notice(payment)
    :ok
  end

  test "lists student-payment notifications", %{conn: conn} do
    admin = admin_fixture()
    seed_payment_notice("Grace Hopper", "GS1 Basics")

    {:ok, _lv, html} = conn |> log_in_user(admin) |> live(~p"/admin/notifications")

    assert html =~ "Notifications"
    assert html =~ "New student payment"
    assert html =~ "Grace Hopper"
    assert html =~ "GS1 Basics"
    assert html =~ "1 unread"
  end

  test "dismiss marks a notification read", %{conn: conn} do
    admin = admin_fixture()
    seed_payment_notice("Alan Turing", "GS1 Basics")

    {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin/notifications")

    [notification] = Notifications.list_for_user(admin)

    html =
      lv
      |> element("#notification-#{notification.id} button", "Dismiss")
      |> render_click()

    assert html =~ "0 unread"
    assert Notifications.list_for_user(admin) |> hd() |> Map.get(:read_at)
  end

  test "mark all read clears the unread count and the sidebar badge", %{conn: conn} do
    admin = admin_fixture()
    seed_payment_notice("Ada Lovelace", "GS1 Basics")
    seed_payment_notice("Katherine Johnson", "GS1 Advanced")

    {:ok, lv, html} = conn |> log_in_user(admin) |> live(~p"/admin/notifications")
    assert html =~ "2 unread"
    assert html =~ "sidebar-notification-count"

    html = lv |> element("button", "Mark all read") |> render_click()
    assert html =~ "0 unread"
    refute html =~ "sidebar-notification-count"
  end

  test "shows the empty state when there is nothing", %{conn: conn} do
    {:ok, _lv, html} =
      conn |> log_in_user(admin_fixture()) |> live(~p"/admin/notifications")

    assert html =~ "Nothing to catch up on."
  end

  test "learners can't reach the admin notifications page", %{conn: conn} do
    {:error, {:redirect, %{to: "/dashboard"}}} =
      conn |> log_in_user(user_fixture()) |> live(~p"/admin/notifications")
  end
end
