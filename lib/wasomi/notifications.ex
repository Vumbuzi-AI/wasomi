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
  alias Wasomi.Payments.Payment
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
  Fans out notifications for a freshly posted course-channel message.

    * Every `@mentioned` member — active learner or alumni — gets an in-app
      `:channel_mention` notification.
    * For an announcement, every active (non-alumni) member who wasn't
      mentioned gets an in-app `:channel_announcement` notification and an
      email.

  The author is never notified, and alumni get nothing unless they were
  explicitly mentioned. Anyone in `present_ids` — members currently viewing
  the channel — is skipped entirely (they already saw the message stream in,
  the way WhatsApp suppresses a notification while you're in the chat).
  Best-effort: the message row has already committed.
  """
  def deliver_channel_message(message, course, members, present_ids \\ []) do
    author_name = channel_author_name(message)
    present = MapSet.new(present_ids)
    members_by_id = Map.new(members, &{&1.user.id, &1})
    mention_ids = Enum.uniq(message.mentioned_user_ids || [])

    announced_ids =
      if message.kind == :announcement do
        members
        |> Enum.filter(fn %{user: user, role: role} ->
          role == :active and user.id != message.user_id and
            not MapSet.member?(present, user.id)
        end)
        |> Enum.map(fn %{user: user} ->
          case notify_channel(
                 user,
                 course,
                 message,
                 :channel_announcement,
                 "New announcement in \"#{course.title}\"",
                 message.body
               ) do
            {:ok, _notification} -> deliver_announcement_email(user, course, message.body)
            _ -> :ok
          end

          user.id
        end)
      else
        []
      end
      |> MapSet.new()

    mention_ids
    |> Enum.reject(&(MapSet.member?(announced_ids, &1) or MapSet.member?(present, &1)))
    |> Enum.each(fn user_id ->
      case members_by_id do
        %{^user_id => %{user: user}} ->
          notify_channel(
            user,
            course,
            message,
            :channel_mention,
            "#{author_name} mentioned you in \"#{course.title}\"",
            message.body
          )

        _ ->
          :ok
      end
    end)

    :ok
  end

  defp notify_channel(user, course, message, kind, title, body) do
    case create_notification(%{
           user_id: user.id,
           course_id: course.id,
           channel_message_id: message.id,
           kind: kind,
           title: title,
           body: channel_excerpt(body)
         }) do
      {:ok, notification} ->
        broadcast(user.id, {:notification_created, notification})
        {:ok, notification}

      {:error, changeset} ->
        Logger.error(
          "Failed to create #{kind} notification for user #{user.id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  defp deliver_announcement_email(user, course, body) do
    UserNotifier.deliver_channel_announcement(user, course, channel_excerpt(body))
  rescue
    error ->
      Logger.error(
        "Failed to send channel announcement email for user #{user.id}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      :error
  end

  defp channel_author_name(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp channel_author_name(_message), do: "Someone"

  @channel_mention_token ~r/@\[([^\]\n]+)\]\(user:\d+\)/

  defp channel_excerpt(text, max \\ 180) do
    text =
      text
      |> to_string()
      |> then(&Regex.replace(@channel_mention_token, &1, "@\\1"))

    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  @doc """
  Confirms a completed course payment to the learner: an in-app
  notification plus a receipt-style email. Best-effort and called after the
  payment and its enrollment have already committed, so a mail or broadcast
  hiccup never rolls anything back.
  """
  def deliver_payment_confirmed(%Payment{} = payment) do
    payment = Repo.preload(payment, [:user, :course])

    try do
      UserNotifier.deliver_payment_receipt(payment, receipt_pdf(payment))
    rescue
      error ->
        Logger.error(
          "Failed to email payment receipt for payment #{payment.id}: " <>
            Exception.format(:error, error, __STACKTRACE__)
        )
    end

    case create_notification(%{
           user_id: payment.user_id,
           course_id: payment.course_id,
           kind: :enrollment_granted,
           title: "Payment confirmed",
           body:
             "Your payment for \"#{payment.course.title}\" is confirmed — you now have full access."
         }) do
      {:ok, notification} ->
        broadcast(payment.user_id, {:notification_created, notification})
        {:ok, notification}

      {:error, changeset} ->
        Logger.error(
          "Failed to create payment_confirmed notification for payment #{payment.id}: " <>
            inspect(changeset)
        )

        {:error, changeset}
    end
  end

  # Best-effort — a failed render just means no attachment on the email.
  defp receipt_pdf(%Payment{} = payment) do
    case Wasomi.Receipts.pdf_for(payment.user, payment.id) do
      {:ok, bytes} -> bytes
      _ -> nil
    end
  rescue
    _ -> nil
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
           conflict_target:
             {:unsafe_fragment,
              "(user_id, course_id, kind) WHERE kind NOT IN ('channel_announcement', 'channel_mention')"}
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
