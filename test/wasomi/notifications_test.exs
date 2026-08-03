defmodule Wasomi.NotificationsTest do
  use Wasomi.DataCase

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
  end
end
