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
      course = course_fixture(status: :published)

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
      course = course_fixture(status: :published)

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

  describe "list_for_user/2" do
    test "lists only the user's notifications newest first and supports a limit" do
      learner = user_fixture()
      other_learner = user_fixture()
      admin = admin_fixture()

      old_course = course_fixture(status: :published, title: "Older course")
      new_course = course_fixture(status: :published, title: "Newer course")
      other_course = course_fixture(status: :published, title: "Other course")

      {:ok, _enrollment} =
        Enrollments.grant_access(learner, admin, %{
          "course_id" => old_course.id,
          "reason" => "Manual enrollment for a partner scholarship"
        })

      {:ok, _enrollment} =
        Enrollments.grant_access(learner, admin, %{
          "course_id" => new_course.id,
          "reason" => "Manual enrollment for a partner scholarship"
        })

      {:ok, _enrollment} =
        Enrollments.grant_access(other_learner, admin, %{
          "course_id" => other_course.id,
          "reason" => "Manual enrollment for a partner scholarship"
        })

      all_notifications = Notifications.list_for_user(learner)

      assert Enum.map(all_notifications, & &1.body) == [
               "You now have access to \"Newer course\". Start learning any time.",
               "You now have access to \"Older course\". Start learning any time."
             ]

      assert [%{body: body}] = Notifications.list_for_user(learner, limit: 1)
      assert body =~ "Newer course"
    end

    test "hides never-started nudges from in-app lists while retaining gone-quiet nudges" do
      learner = user_fixture()
      never_started_course = course_fixture(status: :published, title: "Quiet inbox starter")
      gone_quiet_course = course_fixture(status: :published, title: "Quiet inbox return")

      {:ok, never_started_enrollment} =
        Enrollments.create_pending_enrollment(learner, never_started_course)

      {:ok, gone_quiet_enrollment} =
        Enrollments.create_pending_enrollment(learner, gone_quiet_course)

      assert {:ok, _notification} =
               Notifications.deliver_reengagement_never_started(never_started_enrollment)

      assert {:ok, _notification} =
               Notifications.deliver_reengagement_gone_quiet(gone_quiet_enrollment)

      assert [%{kind: :reengagement_gone_quiet, title: title}] =
               Notifications.list_unread_for_user(learner)

      assert title == "Pick back up in \"Quiet inbox return\""

      refute Enum.any?(
               Notifications.list_for_user(learner),
               &(&1.kind == :reengagement_never_started)
             )
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

  describe "Notification.changeset/2 course scoping" do
    test "requires course_id for a re-engagement kind" do
      learner = user_fixture()

      changeset =
        Notifications.Notification.changeset(%Notifications.Notification{}, %{
          user_id: learner.id,
          kind: :reengagement_never_started,
          title: "Ready to start?",
          body: "Come learn."
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).course_id
    end

    test "does not require course_id for enrollment_granted" do
      learner = user_fixture()

      changeset =
        Notifications.Notification.changeset(%Notifications.Notification{}, %{
          user_id: learner.id,
          kind: :enrollment_granted,
          title: "Access granted",
          body: "You're in."
        })

      assert changeset.valid?
    end
  end

  describe "deliver_reengagement_never_started/1" do
    import Swoosh.TestAssertions

    test "delivers the email and a course-scoped notification" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      assert {:ok, notification} = Notifications.deliver_reengagement_never_started(enrollment)
      assert notification.user_id == learner.id
      assert notification.course_id == course.id
      assert notification.kind == :reengagement_never_started
      assert_email_sent(subject: "Your seat in \"#{course.title}\" is ready when you are")
    end

    test "is idempotent: a second call for the same enrollment sends no second email" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      assert {:ok, %Notifications.Notification{}} =
               Notifications.deliver_reengagement_never_started(enrollment)

      assert {:ok, :already_sent} = Notifications.deliver_reengagement_never_started(enrollment)

      assert Repo.aggregate(
               from(n in Notifications.Notification,
                 where: n.user_id == ^learner.id and n.kind == :reengagement_never_started
               ),
               :count
             ) == 1

      assert_email_sent(subject: "Your seat in \"#{course.title}\" is ready when you are")
      assert_no_email_sent()
    end

    test "releases the reservation when the mailer returns an error" do
      previous_mailer_config = Application.get_env(:wasomi, Wasomi.Mailer)
      on_exit(fn -> Application.put_env(:wasomi, Wasomi.Mailer, previous_mailer_config) end)
      Application.put_env(:wasomi, Wasomi.Mailer, adapter: __MODULE__.FailingMailerAdapter)

      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      capture_log(fn ->
        assert {:error, :provider_down} =
                 Notifications.deliver_reengagement_never_started(enrollment)
      end)

      assert_no_email_sent()

      refute Repo.get_by(Notifications.Notification,
               user_id: learner.id,
               course_id: course.id,
               kind: :reengagement_never_started
             )
    end

    test "releases the reservation when email delivery raises so a retry can send" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)
      broken_enrollment = %{enrollment | user: %{learner | email: 123}}

      capture_log(fn ->
        assert {:error, %Protocol.UndefinedError{}} =
                 Notifications.deliver_reengagement_never_started(broken_enrollment)
      end)

      assert_no_email_sent()

      refute Repo.get_by(Notifications.Notification,
               user_id: learner.id,
               course_id: course.id,
               kind: :reengagement_never_started
             )

      assert {:ok, notification} = Notifications.deliver_reengagement_never_started(enrollment)
      assert notification.user_id == learner.id
      assert_email_sent(subject: "Your seat in \"#{course.title}\" is ready when you are")
    end
  end

  describe "deliver_reengagement_gone_quiet/1" do
    import Swoosh.TestAssertions

    test "delivers the email and a course-scoped notification" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      assert {:ok, notification} = Notifications.deliver_reengagement_gone_quiet(enrollment)
      assert notification.user_id == learner.id
      assert notification.course_id == course.id
      assert notification.kind == :reengagement_gone_quiet
      assert_email_sent(subject: "Pick up right where you left off in \"#{course.title}\"")
    end

    test "is idempotent: a second call for the same enrollment sends no second email" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      assert {:ok, %Notifications.Notification{}} =
               Notifications.deliver_reengagement_gone_quiet(enrollment)

      assert {:ok, :already_sent} = Notifications.deliver_reengagement_gone_quiet(enrollment)

      assert Repo.aggregate(
               from(n in Notifications.Notification,
                 where: n.user_id == ^learner.id and n.kind == :reengagement_gone_quiet
               ),
               :count
             ) == 1
    end

    test "never-started and gone-quiet nudges for the same enrollment don't collide" do
      learner = user_fixture()
      course = course_fixture()
      {:ok, enrollment} = Enrollments.create_pending_enrollment(learner, course)

      assert {:ok, %Notifications.Notification{}} =
               Notifications.deliver_reengagement_never_started(enrollment)

      assert {:ok, %Notifications.Notification{}} =
               Notifications.deliver_reengagement_gone_quiet(enrollment)

      assert Repo.aggregate(
               from(n in Notifications.Notification, where: n.user_id == ^learner.id),
               :count
             ) == 2
    end
  end

  defmodule FailingMailerAdapter do
    use Swoosh.Adapter

    def deliver(_email, _config), do: {:error, :provider_down}
  end
end
