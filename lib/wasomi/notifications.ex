defmodule Wasomi.Notifications do
  @moduledoc """
  Entry point for transactional notifications.

  Delivery is synchronous for the proof-of-concept. Phase 9 can move this
  boundary behind Oban without changing callers in the domain contexts.
  """

  import Ecto.Query, warn: false

  alias Wasomi.Accounts.{User, UserNotifier}
  alias Wasomi.Enrollments.Enrollment
  alias Wasomi.Notifications.Notification
  alias Wasomi.Repo

  @doc """
  Sends the welcome message after a learner confirms their account.

  Confirmation remains successful if the mail provider is temporarily
  unavailable; later notification work can add durable retries.
  """
  def deliver_welcome(%User{} = user) do
    UserNotifier.deliver_welcome(user)
  end

  @doc """
  Delivers the welcome email and creates the in-app notification for an
  admin-granted enrollment, then broadcasts so an open dashboard updates
  live. Both remain best-effort: the enrollment and its audit record have
  already committed by the time this runs.
  """
  def deliver_enrollment_granted(%Enrollment{} = enrollment) do
    enrollment = Repo.preload(enrollment, [:user, :course])

    UserNotifier.deliver_course_access_granted(enrollment.user, enrollment.course)

    {:ok, notification} =
      create_notification(%{
        user_id: enrollment.user_id,
        kind: :enrollment_granted,
        title: "Course access granted",
        body: "You now have access to \"#{enrollment.course.title}\". Start learning any time."
      })

    Phoenix.PubSub.broadcast(
      Wasomi.PubSub,
      "user:#{enrollment.user_id}",
      {:enrollment_granted, enrollment}
    )

    {:ok, notification}
  end

  @doc """
  Lists a user's unread in-app notifications, newest first.
  """
  def list_unread_for_user(%User{id: user_id}) do
    Notification
    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_notification!(id), do: Repo.get!(Notification, id)

  @doc """
  Marks a notification as read.
  """
  def mark_read(%Notification{} = notification) do
    notification
    |> Notification.changeset(%{read_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  defp create_notification(attrs) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end
end
