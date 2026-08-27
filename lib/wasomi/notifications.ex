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

  @hidden_in_app_kinds [
    :reengagement_never_started,
    :reengagement_never_started_2,
    :reengagement_never_started_3
  ]

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
           course_id: enrollment.course_id,
           kind: :enrollment_granted,
           title: "Course access granted",
           body: "You now have access to \"#{enrollment.course.title}\". Start learning any time."
         }) do
      {:ok, notification} ->
        broadcast(enrollment.user_id, {:notification_created, notification})

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
  Delivers touch `touch` (1, 2, or 3) of the "never started" re-engagement
  sequence for one active enrollment, and records the send marker used for
  idempotency. Email-only in the learner experience for every touch, so
  it's hidden from in-app notification lists.

  A no-op if this touch has already fired for this user+course — callers
  running on a cron schedule can call this unconditionally for every
  candidate enrollment without double-sending.
  """
  def deliver_reengagement_never_started(%Enrollment{} = enrollment, touch \\ 1)
      when touch in [1, 2, 3] do
    deliver_reengagement(enrollment, never_started_kind(touch), fn user, course ->
      UserNotifier.deliver_reengagement_never_started(user, course, touch)
    end)
  end

  @doc """
  Delivers touch `touch` (1, 2, or 3) of the "gone quiet" re-engagement
  sequence for one active enrollment, and records the matching in-app
  notification. Same idempotency guarantee as
  `deliver_reengagement_never_started/2`.
  """
  def deliver_reengagement_gone_quiet(%Enrollment{} = enrollment, touch \\ 1)
      when touch in [1, 2, 3] do
    deliver_reengagement(enrollment, gone_quiet_kind(touch), fn user, course ->
      UserNotifier.deliver_reengagement_gone_quiet(user, course, touch)
    end)
  end

  @doc """
  Lists a user's unread in-app notifications, newest first.
  """
  def list_unread_for_user(%User{id: user_id}, opts \\ []) do
    Notification
    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> where([n], n.kind not in ^@hidden_in_app_kinds)
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  @doc """
  Counts visible unread in-app notifications for a user.
  """
  def count_unread_for_user(%User{id: user_id}) do
    Notification
    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> where([n], n.kind not in ^@hidden_in_app_kinds)
    |> Repo.aggregate(:count)
  end

  @doc """
  Lists a user's in-app notification history, newest first. Preloads
  `:course` — callers use it to link a notification straight to the course
  it's about.
  """
  def list_for_user(%User{id: user_id}, opts \\ []) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> where([n], n.kind not in ^@hidden_in_app_kinds)
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
    |> Repo.preload(:course)
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
        |> Repo.preload(:course)

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

  @doc """
  Marks all visible in-app notifications as read for a user.
  """
  def mark_all_read_for_user(%User{id: user_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Notification
    |> where([n], n.user_id == ^user_id and is_nil(n.read_at))
    |> where([n], n.kind not in ^@hidden_in_app_kinds)
    |> Repo.update_all(set: [read_at: now, updated_at: now])
  end

  defp create_notification(attrs) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  # Reserves the notification row first (via a unique index on
  # user_id+course_id+kind, `on_conflict: :nothing`) and only sends the
  # email if this call is the one that created it. This ordering — reserve,
  # then email — is what makes the trigger safe under a race between
  # overlapping job executions: whichever insert loses the conflict skips
  # the email entirely, rather than both racing to send.
  defp deliver_reengagement(%Enrollment{} = enrollment, kind, deliver_email) do
    enrollment = Repo.preload(enrollment, [:user, :course])

    attrs = %{
      user_id: enrollment.user_id,
      course_id: enrollment.course_id,
      kind: kind,
      title: reengagement_title(kind, enrollment.course),
      body: reengagement_body(kind, enrollment.course)
    }

    case %Notification{}
         |> Notification.changeset(attrs)
         |> Repo.insert(
           on_conflict: :nothing,
           conflict_target: [:user_id, :course_id, :kind]
         ) do
      {:ok, %Notification{id: nil}} ->
        {:ok, :already_sent}

      {:ok, notification} ->
        deliver_reserved_reengagement(notification, enrollment, kind, deliver_email)

      {:error, changeset} ->
        Logger.error(
          "Failed to create #{kind} notification for enrollment #{enrollment.id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  defp deliver_reserved_reengagement(notification, enrollment, kind, deliver_email) do
    case deliver_email.(enrollment.user, enrollment.course) do
      {:ok, _email} ->
        broadcast(enrollment.user_id, {:notification_created, notification})
        {:ok, notification}

      {:error, reason} ->
        release_failed_reengagement(notification)

        Logger.error(
          "Failed to send #{kind} email for enrollment #{enrollment.id}: #{inspect(reason)}"
        )

        {:error, reason}

      unexpected ->
        release_failed_reengagement(notification)

        Logger.error(
          "Failed to send #{kind} email for enrollment #{enrollment.id}: " <>
            "unexpected mailer result #{inspect(unexpected)}"
        )

        {:error, {:unexpected_delivery_result, unexpected}}
    end
  rescue
    error ->
      release_failed_reengagement(notification)

      Logger.error(
        "Failed to send #{kind} email for enrollment #{enrollment.id}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      {:error, error}
  end

  defp release_failed_reengagement(%Notification{} = notification) do
    case Repo.delete(notification) do
      {:ok, _notification} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to release re-engagement reservation: #{inspect(changeset)}")
        :error
    end
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  defp broadcast(user_id, message) do
    Phoenix.PubSub.broadcast(Wasomi.PubSub, "user:#{user_id}", message)
  end

  defp never_started_kind(1), do: :reengagement_never_started
  defp never_started_kind(2), do: :reengagement_never_started_2
  defp never_started_kind(3), do: :reengagement_never_started_3

  defp gone_quiet_kind(1), do: :reengagement_gone_quiet
  defp gone_quiet_kind(2), do: :reengagement_gone_quiet_2
  defp gone_quiet_kind(3), do: :reengagement_gone_quiet_3

  defp reengagement_title(:reengagement_never_started, course),
    do: "Ready to start \"#{course.title}\"?"

  defp reengagement_title(:reengagement_never_started_2, course),
    do: "Still thinking about \"#{course.title}\"?"

  defp reengagement_title(:reengagement_never_started_3, course),
    do: "Last call: your seat in \"#{course.title}\""

  defp reengagement_title(:reengagement_gone_quiet, course),
    do: "Pick back up in \"#{course.title}\""

  defp reengagement_title(:reengagement_gone_quiet_2, course),
    do: "Your progress in \"#{course.title}\" is still saved"

  defp reengagement_title(:reengagement_gone_quiet_3, course),
    do: "One last nudge for \"#{course.title}\""

  defp reengagement_body(:reengagement_never_started, course) do
    "You're enrolled in \"#{course.title}\" but haven't started yet. Jump in whenever you're ready."
  end

  defp reengagement_body(:reengagement_never_started_2, course) do
    "Your spot in \"#{course.title}\" is still open. It's not too late to get started."
  end

  defp reengagement_body(:reengagement_never_started_3, course) do
    "This is the last reminder about \"#{course.title}\" — no pressure either way, but your access " <>
      "hasn't gone anywhere if you'd like to jump in."
  end

  defp reengagement_body(:reengagement_gone_quiet, course) do
    "You made progress in \"#{course.title}\", then went quiet. Your place is saved — come finish it."
  end

  defp reengagement_body(:reengagement_gone_quiet_2, course) do
    "Still thinking about finishing \"#{course.title}\"? Everything you completed is exactly where you left it."
  end

  defp reengagement_body(:reengagement_gone_quiet_3, course) do
    "Last check-in on \"#{course.title}\" — your progress stays saved either way, so there's no rush."
  end
end
