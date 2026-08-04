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
  Subscribes the calling process to a user's real-time notification topic.

  `Wasomi.Payments` also broadcasts payment confirmations on this same
  `"user:\#{id}"` topic — subscribing once here (e.g. from `DashboardLive`)
  covers both payment and in-app-notification events.
  """
  def subscribe(%User{id: id}), do: Phoenix.PubSub.subscribe(Wasomi.PubSub, "user:#{id}")

  require Logger

  @doc """
  Delivers the welcome email and creates the in-app notification for an
  admin-granted enrollment, then broadcasts so an open dashboard updates
  live. Both remain best-effort: the enrollment and its audit record have
  already committed by the time this runs.
  """
  def deliver_enrollment_granted(%Enrollment{} = enrollment) do
    enrollment = Repo.preload(enrollment, [:user, :course])

    try do
      UserNotifier.deliver_course_access_granted(enrollment.user, enrollment.course)
    rescue
      error ->
        Logger.error(
          "Failed to email enrollment #{enrollment.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
        )
    end

    case create_notification(%{
           user_id: enrollment.user_id,
           kind: :enrollment_granted,
           title: "Course access granted",
           body: "You now have access to \"#{enrollment.course.title}\". Start learning any time."
         }) do
      {:ok, notification} ->
        Phoenix.PubSub.broadcast(
          Wasomi.PubSub,
          "user:#{enrollment.user_id}",
          {:enrollment_granted, enrollment}
        )

        {:ok, notification}

      {:error, changeset} ->
        Logger.error(
          "Failed to create notification for enrollment #{enrollment.id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
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

  @doc """
  Gets a user's own notification, or `nil` if it doesn't exist or belongs to
  someone else — callers must not be able to look up or mark read a
  notification that isn't theirs. A tampered id fails soft (`nil`) rather
  than crashing the caller's LiveView connection.
  """
  def get_notification(_user, nil), do: nil

  def get_notification(%User{id: user_id}, id) do
    case Ecto.Type.cast(:integer, id) do
      {:ok, int_id} when not is_nil(int_id) ->
        Notification
        |> where([n], n.id == ^int_id and n.user_id == ^user_id)
        |> Repo.one()

      _ ->
        nil
    end
  end

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
