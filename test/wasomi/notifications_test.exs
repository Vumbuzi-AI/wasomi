defmodule Wasomi.NotificationsTest do
  use Wasomi.DataCase

  import ExUnit.CaptureLog
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.{Accounts, Enrollments, Notifications}

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Accounts.update_user_role(user, :admin)
    admin
  end

  describe "get_notification/2" do
    test "returns the notification when it belongs to the given user" do
      learner = user_fixture()
      admin = admin_fixture()
      course = course_fixture()

      {:ok, _enrollment} =
        Enrollments.grant_access(learner, admin, %{
          "course_id" => course.id,
          "reason" => "Manual enrollment for a partner scholarship"
        })

      [notification] = Notifications.list_unread_for_user(learner)

      assert %Notifications.Notification{id: id} =
               Notifications.get_notification(learner, notification.id)

      assert id == notification.id
    end

    test "returns nil when the notification belongs to someone else" do
      learner = user_fixture()
      stranger = user_fixture()
      admin = admin_fixture()
      course = course_fixture()

      {:ok, _enrollment} =
        Enrollments.grant_access(learner, admin, %{
          "course_id" => course.id,
          "reason" => "Manual enrollment for a partner scholarship"
        })

      [notification] = Notifications.list_unread_for_user(learner)

      assert Notifications.get_notification(stranger, notification.id) == nil
    end

    test "returns nil for non-integer or malformed id strings without crashing" do
      learner = user_fixture()

      assert Notifications.get_notification(learner, "foo") == nil
      assert Notifications.get_notification(learner, "123bar") == nil
      assert Notifications.get_notification(learner, nil) == nil
    end
  end

  describe "deliver_enrollment_granted/1" do
    import Swoosh.TestAssertions

    test "delivers notification and email successfully for active enrollment" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      assert {:ok, notification} = Notifications.deliver_enrollment_granted(enrollment)
      assert notification.user_id == learner.id
      assert notification.kind == :enrollment_granted
      assert_email_sent(subject: "You now have access to #{course.title}")
    end

    test "does not crash process if notification insertion fails" do
      learner = user_fixture()
      course = course_fixture()
      # Enrollment with invalid user_id to simulate notification insertion error
      enrollment = %Wasomi.Enrollments.Enrollment{
        id: 99999,
        user_id: nil,
        user: learner,
        course: course
      }

      capture_log(fn ->
        assert {:error, %Ecto.Changeset{}} = Notifications.deliver_enrollment_granted(enrollment)
      end)
    end

    test "still creates the in-app notification when the email delivery raises" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      # An email recipient Swoosh cannot format raises inside UserNotifier.deliver/3.
      broken_enrollment = %{enrollment | user: %{learner | email: 123}}

      capture_log(fn ->
        assert {:ok, notification} = Notifications.deliver_enrollment_granted(broken_enrollment)
        assert notification.user_id == learner.id
      end)

      assert_no_email_sent()
    end
  end
end
