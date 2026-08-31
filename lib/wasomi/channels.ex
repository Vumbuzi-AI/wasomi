defmodule Wasomi.Channels do
  @moduledoc """
  Course cohort channels: one shared discussion space per course for its
  enrolled learners, its alumni (learners who have completed it) and admins.

  Membership is **derived**, never stored: an active enrollment grants access,
  losing it (refund/removal) revokes access on the next check. Completing the
  course turns a member into an alumnus — still able to read and post, but
  excluded from routine announcement notifications.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.{Course, CourseModule, Lecture}
  alias Wasomi.Channels.{Channel, Message, Reaction, Read}
  alias Wasomi.Enrollments
  alias Wasomi.Enrollments.Enrollment
  alias Wasomi.Learning
  alias Wasomi.Learning.LectureProgress
  alias Wasomi.Notifications
  alias Wasomi.Repo

  @recent_limit 50
  @topic_prefix "channel:"

  # A mention is stored in the body as the stable token `@[Display Name](user:42)`.
  @mention_token_regex ~r/@\[[^\]\n]+\]\(user:(\d+)\)/
  @all_mention_regex ~r/(^|[^\p{L}\p{N}_])@(all|everyone)\b/iu

  ## ------------------------------------------------------------------
  ## Channel lifecycle
  ## ------------------------------------------------------------------

  @doc """
  Returns the course's channel, creating it on first use. The channel row
  carries no state of its own — it exists to anchor messages and reads.
  """
  def get_or_create_for_course(%Course{id: course_id}) do
    case Repo.get_by(Channel, course_id: course_id) do
      %Channel{} = channel ->
        channel

      nil ->
        %Channel{}
        |> Channel.changeset(%{course_id: course_id})
        |> Repo.insert()
        |> case do
          {:ok, channel} -> channel
          # Lost a race with a concurrent first visit — read the winner back.
          {:error, _changeset} -> Repo.get_by!(Channel, course_id: course_id)
        end
    end
  end

  def get_channel_for_course(%Course{id: course_id}), do: get_channel_for_course(course_id)
  def get_channel_for_course(course_id), do: Repo.get_by(Channel, course_id: course_id)

  @doc """
  `%{message_count: integer, last_activity_at: DateTime | nil}` for the admin
  course view. Counts live (non-deleted) messages only.
  """
  def stats_for_course(%Course{} = course) do
    case get_channel_for_course(course) do
      nil ->
        %{message_count: 0, last_activity_at: nil}

      %Channel{id: channel_id} ->
        Repo.one(
          from m in Message,
            where: m.channel_id == ^channel_id and is_nil(m.deleted_at),
            select: %{count: count(m.id), last: max(m.inserted_at)}
        )
        |> case do
          %{count: count, last: last} -> %{message_count: count, last_activity_at: last}
          _ -> %{message_count: 0, last_activity_at: nil}
        end
    end
  end

  @doc """
  A channel is read-only once its course is archived. Draft/published courses
  keep an open channel so a course pulled back for revision doesn't silence
  its cohort.
  """
  def read_only?(%Course{status: :archived}), do: true
  def read_only?(%Course{}), do: false

  @doc """
  Every course's channel at a glance for the admin discussions hub — most
  recently active first, then alphabetical. Each row:

      %{course: %Course{}, message_count: n, last_activity_at: dt | nil,
        member_count: n, unread: n, read_only?: bool}
  """
  def admin_channel_list(%User{} = admin) do
    build_channel_list(admin, Repo.all(from c in Course, order_by: [asc: c.title]))
  end

  @doc """
  The channels a learner belongs to (any active enrolment — active learners
  and alumni), same shape as `admin_channel_list/1`.
  """
  def learner_channel_list(%User{id: user_id} = learner) do
    courses =
      Repo.all(
        from c in Course,
          join: e in Enrollment,
          on: e.course_id == c.id,
          where: e.user_id == ^user_id and e.status == :active,
          order_by: [asc: c.title]
      )

    build_channel_list(learner, courses)
  end

  defp build_channel_list(%User{id: viewer_id}, courses) do
    course_ids = Enum.map(courses, & &1.id)
    admin_count = Repo.aggregate(from(u in User, where: u.role == :admin), :count)

    active_by_course =
      from(e in Enrollment,
        where: e.status == :active and e.course_id in ^course_ids,
        group_by: e.course_id,
        select: {e.course_id, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()

    stats_by_course =
      from(m in Message,
        join: ch in Channel,
        on: ch.id == m.channel_id,
        where: is_nil(m.deleted_at) and ch.course_id in ^course_ids,
        group_by: ch.course_id,
        select: {ch.course_id, %{count: count(m.id), last: max(m.inserted_at)}}
      )
      |> Repo.all()
      |> Map.new()

    unread_by_course =
      from(m in Message,
        join: ch in Channel,
        on: ch.id == m.channel_id,
        left_join: r in Read,
        on: r.channel_id == ch.id and r.user_id == ^viewer_id,
        where:
          is_nil(m.deleted_at) and ch.course_id in ^course_ids and m.user_id != ^viewer_id and
            (is_nil(r.last_read_at) or m.inserted_at > r.last_read_at),
        group_by: ch.course_id,
        select: {ch.course_id, count(m.id)}
      )
      |> Repo.all()
      |> Map.new()

    courses
    |> Enum.map(fn course ->
      stats = Map.get(stats_by_course, course.id, %{count: 0, last: nil})

      %{
        course: course,
        message_count: stats.count,
        last_activity_at: stats.last,
        member_count: Map.get(active_by_course, course.id, 0) + admin_count,
        unread: Map.get(unread_by_course, course.id, 0),
        read_only?: course.status == :archived
      }
    end)
    |> Enum.sort_by(
      &{&1.last_activity_at == nil, negative_unix(&1.last_activity_at),
       String.downcase(&1.course.title)}
    )
  end

  defp negative_unix(nil), do: 0
  defp negative_unix(%DateTime{} = dt), do: -DateTime.to_unix(dt, :microsecond)

  ## ------------------------------------------------------------------
  ## Membership (derived)
  ## ------------------------------------------------------------------

  @doc """
  One of `:admin`, `:alumni`, `:active`, or `nil` (not a member).
  """
  def member_role(%User{role: :admin}, %Course{}), do: :admin

  def member_role(%User{} = user, %Course{} = course) do
    cond do
      not Enrollments.can_access_course?(user, course) -> nil
      Learning.course_complete?(user, course) -> :alumni
      true -> :active
    end
  end

  def member_role(_user, _course), do: nil

  def member?(user, course), do: not is_nil(member_role(user, course))

  @doc """
  `:read` for any member, `:post` for any member while the channel is open,
  `:moderate` for admins only.
  """
  def can?(user, course, action)

  def can?(user, course, :read), do: member?(user, course)

  def can?(user, course, :post) do
    not read_only?(course) and member?(user, course)
  end

  def can?(%User{role: :admin}, _course, :moderate), do: true
  def can?(_user, _course, :moderate), do: false

  def authorize(user, course, action) do
    if can?(user, course, action), do: :ok, else: {:error, :forbidden}
  end

  @doc """
  Everyone reachable in the channel — active learners, alumni and admins —
  as `%{user: %User{}, role: atom}`, sorted by display name. Drives the
  member list and `@mention` autocomplete.
  """
  def list_members(%Course{id: course_id}) do
    enrolled =
      from(e in Enrollment,
        where: e.course_id == ^course_id and e.status == :active,
        join: u in assoc(e, :user),
        select: u
      )
      |> Repo.all()

    admins = from(u in User, where: u.role == :admin) |> Repo.all()
    completed = completed_user_ids(course_id)

    (enrolled ++ admins)
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(fn user ->
      %{user: user, role: role_for(user, completed)}
    end)
    |> Enum.sort_by(&String.downcase(&1.user.name || &1.user.email || ""))
  end

  ## ------------------------------------------------------------------
  ## Messages
  ## ------------------------------------------------------------------

  @doc """
  Newest `limit` messages (default #{@recent_limit}) for the channel, oldest
  first for rendering. Pass `before:` a `DateTime` to page backwards.
  Soft-deleted messages are included as tombstones; callers render them as
  "removed".
  """
  def list_messages(%Channel{id: channel_id}, opts \\ []) do
    limit = opts[:limit] || @recent_limit

    Message
    |> where([m], m.channel_id == ^channel_id)
    |> then(fn q ->
      case opts[:before] do
        %DateTime{} = t -> where(q, [m], m.inserted_at < ^t)
        _ -> q
      end
    end)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> preload([:user, :deleted_by, :reactions])
    |> Repo.all()
    |> Enum.reverse()
  end

  def pinned_messages(%Channel{id: channel_id}) do
    Message
    |> where(
      [m],
      m.channel_id == ^channel_id and not is_nil(m.pinned_at) and is_nil(m.deleted_at)
    )
    |> order_by([m], desc: m.pinned_at, desc: m.id)
    |> preload([:user, :reactions])
    |> Repo.all()
  end

  def get_message(id),
    do: Repo.get(Message, id) |> Repo.preload([:user, :deleted_by, :reactions, channel: :course])

  @doc """
  Posts an ordinary message from a member. Resolves `@mentions` against the
  member list, broadcasts to open sessions, then delivers mention
  notifications (best-effort).
  """
  def post_message(%User{} = user, %Channel{} = channel, body) do
    create_message(user, channel, body, :message)
  end

  @doc """
  Posts a pinned announcement from an admin. Notifies active (non-alumni)
  members by email and in-app; alumni and the author are skipped.
  """
  def post_announcement(%User{role: :admin} = admin, %Channel{} = channel, body) do
    create_message(admin, channel, body, :announcement)
  end

  def post_announcement(_user, _channel, _body), do: {:error, :forbidden}

  defp create_message(user, channel, body, kind) do
    course = channel_course(channel)

    with :ok <- authorize(user, course, :post),
         :ok <- authorize_kind(user, kind) do
      members = list_members(course)
      pinned_at = if kind == :announcement, do: now(), else: nil

      attrs = %{
        channel_id: channel.id,
        user_id: user.id,
        body: body,
        kind: kind,
        pinned_at: pinned_at,
        mentioned_user_ids: resolve_mentions(body, members, user)
      }

      # Whoever is looking at the channel right now already sees the message
      # stream in — like WhatsApp, don't also push them a notification. `@all`
      # is a deliberate broadcast ping though, so it reaches everyone (bar the
      # sender) regardless of who's currently watching.
      broadcast_ping? = user.role == :admin and Regex.match?(@all_mention_regex, body || "")
      present = if broadcast_ping?, do: [user.id], else: present_user_ids(channel)

      case %Message{} |> Message.changeset(attrs) |> Repo.insert() do
        {:ok, message} ->
          message = %{message | user: user, reactions: []}
          broadcast(channel.id, {:message_created, message})
          run_side_effect(fn -> deliver_notifications(message, course, members, present) end)
          {:ok, message}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp authorize_kind(%User{role: :admin}, :announcement), do: :ok
  defp authorize_kind(_user, :announcement), do: {:error, :forbidden}
  defp authorize_kind(_user, :message), do: :ok

  @doc """
  Soft-deletes a message. Admins may delete any message; other members may
  delete only their own, and only while the channel is open.
  """
  def delete_message(%User{} = user, %Message{} = message) do
    message = Repo.preload(message, channel: :course)
    course = message.channel.course

    if can_delete?(user, message, course) do
      {:ok, deleted} = message |> Message.delete_changeset(user) |> Repo.update()
      broadcast(message.channel_id, {:message_deleted, message.id})
      {:ok, deleted}
    else
      {:error, :forbidden}
    end
  end

  defp can_delete?(%User{role: :admin}, _message, _course), do: true
  defp can_delete?(_user, _message, %Course{status: :archived}), do: false
  defp can_delete?(%User{id: uid}, %Message{user_id: uid}, _course), do: true
  defp can_delete?(_user, _message, _course), do: false

  def pin_message(%User{role: :admin}, %Message{} = message) do
    {:ok, pinned} = message |> Ecto.Changeset.change(pinned_at: now()) |> Repo.update()
    broadcast(message.channel_id, {:message_updated, Repo.preload(pinned, [:user, :reactions])})
    {:ok, pinned}
  end

  def pin_message(_user, _message), do: {:error, :forbidden}

  def unpin_message(%User{role: :admin}, %Message{} = message) do
    {:ok, unpinned} = message |> Ecto.Changeset.change(pinned_at: nil) |> Repo.update()
    broadcast(message.channel_id, {:message_updated, Repo.preload(unpinned, [:user, :reactions])})
    {:ok, unpinned}
  end

  def unpin_message(_user, _message), do: {:error, :forbidden}

  ## ------------------------------------------------------------------
  ## Reactions
  ## ------------------------------------------------------------------

  @doc "The emoji set offered in the reaction picker."
  def reaction_emojis, do: Reaction.allowed()

  @message_emojis ~w(
    😀 😄 😁 😆 😅 😂 🤣 🙂 😉 😊 😍 😘 😜 🤪 🤔 😐
    😴 😇 🥳 😎 🤓 😕 😟 😢 😭 😤 😠 🤯 😱 🥺 🙄 😬
    👍 👎 👏 🙌 🙏 💪 👋 🔥 💯 ✅ ❌ ⭐ 🎉 ❤️ 💔 👀
  )

  @doc "Curated emoji set for the message composer's inline picker."
  def message_emojis, do: @message_emojis

  @doc """
  Adds the reaction if the member hasn't used that emoji on the message yet,
  removes it otherwise. Broadcasts `{:message_reacted, message_id}`.
  """
  def toggle_reaction(%User{} = user, %Message{} = message, emoji) do
    message = Repo.preload(message, channel: :course)

    with :ok <- authorize(user, message.channel.course, :read),
         true <- emoji in Reaction.allowed() do
      case Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji) do
        %Reaction{} = existing ->
          Repo.delete(existing)

        nil ->
          %Reaction{}
          |> Reaction.changeset(%{message_id: message.id, user_id: user.id, emoji: emoji})
          |> Repo.insert(on_conflict: :nothing)
      end

      broadcast(message.channel_id, {:message_reacted, message.id})
      {:ok, message.id}
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  Groups a message's reactions for rendering:
  `[%{emoji: "👍", count: 3, mine?: true}]`, most-used first.
  """
  def group_reactions(reactions, current_user_id) when is_list(reactions) do
    reactions
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, list} ->
      %{
        emoji: emoji,
        count: length(list),
        mine?: Enum.any?(list, &(&1.user_id == current_user_id))
      }
    end)
    |> Enum.sort_by(&{-&1.count, &1.emoji})
  end

  def group_reactions(_reactions, _current_user_id), do: []

  ## ------------------------------------------------------------------
  ## Typing indicator
  ## ------------------------------------------------------------------

  def broadcast_typing(%Channel{id: channel_id}, %User{} = user, typing?) do
    broadcast(
      channel_id,
      {:typing, %{user_id: user.id, name: typing_name(user), typing: typing?}}
    )
  end

  defp typing_name(%User{first_name: first_name}) when is_binary(first_name) and first_name != "",
    do: first_name

  defp typing_name(%User{name: name}) when is_binary(name) and name != "",
    do: name |> String.split() |> List.first()

  defp typing_name(%User{email: email}) when is_binary(email), do: email

  ## ------------------------------------------------------------------
  ## Unread tracking
  ## ------------------------------------------------------------------

  def unread_count(%User{id: user_id}, %Channel{id: channel_id}) do
    last_read = read_marker(channel_id, user_id)

    Message
    |> where([m], m.channel_id == ^channel_id and is_nil(m.deleted_at) and m.user_id != ^user_id)
    |> then(fn q ->
      if last_read, do: where(q, [m], m.inserted_at > ^last_read), else: q
    end)
    |> Repo.aggregate(:count)
  end

  def mark_read(%User{id: user_id}, %Channel{id: channel_id}) do
    stamp = DateTime.utc_now()

    %Read{}
    |> Read.changeset(%{channel_id: channel_id, user_id: user_id, last_read_at: stamp})
    |> Repo.insert(
      on_conflict: [set: [last_read_at: stamp, updated_at: stamp]],
      conflict_target: [:channel_id, :user_id]
    )
  end

  ## ------------------------------------------------------------------
  ## PubSub
  ## ------------------------------------------------------------------

  def topic(%Channel{id: id}), do: topic(id)
  def topic(channel_id), do: @topic_prefix <> to_string(channel_id)

  def subscribe(%Channel{} = channel), do: Phoenix.PubSub.subscribe(Wasomi.PubSub, topic(channel))

  @doc """
  User ids currently viewing the channel (from `WasomiWeb.Presence`, keyed
  by user id in `WasomiWeb.ChannelLive`).
  """
  def present_user_ids(%Channel{} = channel) do
    channel
    |> topic()
    |> WasomiWeb.Presence.list()
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
  rescue
    _ -> []
  end

  defp broadcast(channel_id, message) do
    Phoenix.PubSub.broadcast(Wasomi.PubSub, topic(channel_id), message)
  end

  ## ------------------------------------------------------------------
  ## Internals
  ## ------------------------------------------------------------------

  defp run_side_effect(fun) do
    case Application.get_env(:wasomi, :channel_side_effects, :async) do
      :sync ->
        fun.()

      _ ->
        Task.Supervisor.start_child(Wasomi.TaskSupervisor, fun)
        :ok
    end
  end

  defp deliver_notifications(%Message{} = message, course, members, present_ids) do
    Notifications.deliver_channel_message(message, course, members, present_ids)
  rescue
    error ->
      Logger.error(
        "Failed to deliver channel notifications for message #{message.id}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      :error
  end

  # Mentions are resolved from the stable `@[Name](user:42)` tokens the
  # composer encodes, never by matching display-name text. `@all` / `@everyone`
  # fans out to every member, but only when the author is an admin. The author
  # is never mentioned, and ids that aren't members are dropped.
  defp resolve_mentions(_body, [], _author), do: []

  defp resolve_mentions(body, members, %User{} = author) do
    body = body || ""
    member_ids = MapSet.new(members, & &1.user.id)

    explicit =
      @mention_token_regex
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.map(fn [id] -> String.to_integer(id) end)

    everyone =
      if author.role == :admin and Regex.match?(@all_mention_regex, body) do
        Enum.map(members, & &1.user.id)
      else
        []
      end

    (explicit ++ everyone)
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(member_ids, &1))
    |> Enum.reject(&(&1 == author.id))
  end

  defp role_for(%User{role: :admin}, _completed), do: :admin

  defp role_for(%User{id: id}, completed) do
    if MapSet.member?(completed, id), do: :alumni, else: :active
  end

  defp completed_user_ids(course_id) do
    lecture_ids =
      Repo.all(
        from l in Lecture,
          join: m in CourseModule,
          on: m.id == l.module_id,
          where: m.course_id == ^course_id,
          select: l.id
      )

    total = length(lecture_ids)

    if total == 0 do
      MapSet.new()
    else
      Repo.all(
        from p in LectureProgress,
          where: p.lecture_id in ^lecture_ids and p.status == :completed,
          group_by: p.user_id,
          having: count(p.id) == ^total,
          select: p.user_id
      )
      |> MapSet.new()
    end
  end

  defp channel_course(%Channel{} = channel) do
    channel = Repo.preload(channel, :course)
    channel.course
  end

  defp read_marker(channel_id, user_id) do
    Repo.one(
      from r in Read,
        where: r.channel_id == ^channel_id and r.user_id == ^user_id,
        select: r.last_read_at
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
