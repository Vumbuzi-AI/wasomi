defmodule Wasomi.ChannelsTest do
  use Wasomi.DataCase, async: true

  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.ChannelsFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures

  alias Wasomi.Channels
  alias Wasomi.Notifications.Notification

  defp admin_fixture(attrs \\ %{}) do
    {:ok, admin} = attrs |> user_fixture() |> Wasomi.Accounts.update_user_role(:admin)
    admin
  end

  defp course_with_lecture(status \\ :published) do
    course = course_fixture(status: status)
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)
    {Wasomi.Catalog.get_course_by_slug!(course.slug), lecture}
  end

  defp active_learner(course, attrs \\ %{}) do
    user = user_fixture(attrs)
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)
    user
  end

  # Presence syncs asynchronously — wait until this process's track is visible.
  defp track_present!(channel, user_id) do
    {:ok, _} =
      WasomiWeb.Presence.track(self(), Channels.topic(channel), to_string(user_id), %{})

    Enum.reduce_while(1..50, nil, fn _, _ ->
      if user_id in Channels.present_user_ids(channel),
        do: {:halt, :ok},
        else: Process.sleep(10) && {:cont, nil}
    end)
  end

  describe "get_or_create_for_course/1" do
    test "creates once, then returns the same row" do
      {course, _lecture} = course_with_lecture()

      channel = Channels.get_or_create_for_course(course)
      assert channel.id
      assert Channels.get_or_create_for_course(course).id == channel.id
    end
  end

  describe "member_role/2" do
    setup do
      {course, lecture} = course_with_lecture()
      %{course: course, lecture: lecture}
    end

    test "admin is always :admin", %{course: course} do
      assert Channels.member_role(admin_fixture(), course) == :admin
    end

    test "an active enrollment is :active", %{course: course} do
      assert Channels.member_role(active_learner(course), course) == :active
    end

    test "a completed learner is :alumni", %{course: course, lecture: lecture} do
      learner = active_learner(course)
      complete_lecture_via_progress!(learner, lecture)

      assert Channels.member_role(learner, course) == :alumni
    end

    test "a pending enrollment is not a member", %{course: course} do
      user = user_fixture()
      enrollment_fixture(user_id: user.id, course_id: course.id, status: :pending)

      assert Channels.member_role(user, course) == nil
    end

    test "someone with no enrollment is not a member", %{course: course} do
      assert Channels.member_role(user_fixture(), course) == nil
    end
  end

  describe "can?/3 and authorize/3" do
    test "archived course makes the channel read-only but still readable" do
      {course, _lecture} = course_with_lecture(:archived)
      learner = active_learner(course)

      assert Channels.can?(learner, course, :read)
      refute Channels.can?(learner, course, :post)
      assert Channels.authorize(learner, course, :post) == {:error, :forbidden}
    end

    test "moderation is admin-only" do
      {course, _lecture} = course_with_lecture()

      refute Channels.can?(active_learner(course), course, :moderate)
      assert Channels.can?(admin_fixture(), course, :moderate)
    end
  end

  describe "post_message/3" do
    setup do
      {course, lecture} = course_with_lecture()
      %{course: course, lecture: lecture, channel: channel_fixture(course)}
    end

    test "an active member can post", %{course: course, channel: channel} do
      assert {:ok, message} = Channels.post_message(active_learner(course), channel, "Hi all")
      assert message.body == "Hi all"
      assert message.kind == :message
    end

    test "an alumnus can still post", %{course: course, lecture: lecture, channel: channel} do
      learner = active_learner(course)
      complete_lecture_via_progress!(learner, lecture)

      assert {:ok, _message} = Channels.post_message(learner, channel, "Loved this course")
    end

    test "a non-member cannot post", %{channel: channel} do
      assert Channels.post_message(user_fixture(), channel, "let me in") == {:error, :forbidden}
    end

    test "nobody can post once the course is archived", %{
      course: course,
      channel: channel
    } do
      learner = active_learner(course)
      {:ok, _} = Wasomi.Catalog.archive_course(course)

      assert Channels.post_message(learner, channel, "hello") == {:error, :forbidden}
    end

    test "blank messages are rejected", %{course: course, channel: channel} do
      assert {:error, changeset} = Channels.post_message(active_learner(course), channel, "   ")
      assert %{body: _} = errors_on(changeset)
    end
  end

  describe "post_announcement/3" do
    setup do
      {course, lecture} = course_with_lecture()
      %{course: course, lecture: lecture, channel: channel_fixture(course)}
    end

    test "an admin posts a pinned announcement", %{channel: channel} do
      assert {:ok, message} = Channels.post_announcement(admin_fixture(), channel, "Welcome!")
      assert message.kind == :announcement
      assert message.pinned_at
      assert [pinned] = Channels.pinned_messages(channel)
      assert pinned.id == message.id
    end

    test "a learner cannot post an announcement", %{course: course, channel: channel} do
      assert Channels.post_announcement(active_learner(course), channel, "hi") ==
               {:error, :forbidden}
    end

    test "notifies active members by email and in-app, skipping alumni and author", %{
      course: course,
      lecture: lecture,
      channel: channel
    } do
      active = active_learner(course, %{name: "Active Amaya"})
      alum = active_learner(course, %{name: "Alum Ada"})
      complete_lecture_via_progress!(alum, lecture)
      admin = admin_fixture(%{name: "Admin Ann"})

      {:ok, _} = Channels.post_announcement(admin, channel, "Certificates go out Friday")

      # exactly one notification — the active learner's, not the alum's or the admin's
      assert [notification] = Repo.all(Notification)
      assert notification.user_id == active.id
      assert notification.kind == :channel_announcement
      assert notification.course_id == course.id
      assert_email_sent(subject: "New announcement in #{course.title}")
    end
  end

  describe "@mentions" do
    setup do
      {course, _lecture} = course_with_lecture()
      %{course: course, channel: channel_fixture(course)}
    end

    test "a member mentioned via a token gets a :channel_mention notification", %{
      course: course,
      channel: channel
    } do
      author = active_learner(course, %{name: "Wanjiru"})
      mentioned = active_learner(course, %{name: "Otieno"})

      {:ok, message} =
        Channels.post_message(
          author,
          channel,
          "hey @[Otieno](user:#{mentioned.id}) look at module 2"
        )

      assert mentioned.id in message.mentioned_user_ids

      assert [notification] = Repo.all(Notification)
      assert notification.user_id == mentioned.id
      assert notification.kind == :channel_mention
      assert notification.channel_message_id == message.id
      # the raw token is prettified in the body
      assert notification.body == "hey @Otieno look at module 2"
    end

    test "plain @name text (no token) resolves to nothing", %{course: course, channel: channel} do
      author = active_learner(course, %{name: "Wanjiru"})
      _other = active_learner(course, %{name: "Otieno"})

      {:ok, message} = Channels.post_message(author, channel, "hey @Otieno look at module 2")

      assert message.mentioned_user_ids == []
      assert Repo.all(Notification) == []
    end

    test "a member currently viewing the channel is not notified", %{
      course: course,
      channel: channel
    } do
      author = active_learner(course, %{name: "Wanjiru"})
      mentioned = active_learner(course, %{name: "Otieno"})

      track_present!(channel, mentioned.id)

      {:ok, _message} =
        Channels.post_message(author, channel, "look @[Otieno](user:#{mentioned.id})")

      assert Repo.all(Notification) == []
    end

    test "a token pointing at the author is ignored", %{course: course, channel: channel} do
      author = active_learner(course, %{name: "Kamau"})

      {:ok, message} =
        Channels.post_message(author, channel, "note to self @[Kamau](user:#{author.id})")

      assert message.mentioned_user_ids == []
      assert Repo.all(Notification) == []
    end

    test "a token for a non-member is dropped", %{course: course, channel: channel} do
      author = active_learner(course, %{name: "Kamau"})
      outsider = user_fixture(%{name: "Outsider"})

      {:ok, message} =
        Channels.post_message(author, channel, "ping @[Outsider](user:#{outsider.id})")

      assert message.mentioned_user_ids == []
    end

    test "@all from an admin mentions every other member", %{course: course, channel: channel} do
      admin = admin_fixture(%{name: "Admin Ann"})
      one = active_learner(course, %{name: "One"})
      two = active_learner(course, %{name: "Two"})

      {:ok, message} = Channels.post_message(admin, channel, "heads up @all")

      assert Enum.sort(message.mentioned_user_ids) == Enum.sort([one.id, two.id])
      assert Repo.aggregate(where(Notification, kind: :channel_mention), :count) == 2
    end

    test "@all still reaches a member who is currently viewing the channel", %{
      course: course,
      channel: channel
    } do
      admin = admin_fixture(%{name: "Admin Ann"})
      watching = active_learner(course, %{name: "Watcher"})

      track_present!(channel, watching.id)

      {:ok, _message} = Channels.post_message(admin, channel, "everyone read this @all")

      assert Repo.aggregate(where(Notification, kind: :channel_mention), :count) == 1
      assert [%{user_id: uid}] = Repo.all(Notification)
      assert uid == watching.id
    end

    test "@all from a learner does nothing", %{course: course, channel: channel} do
      author = active_learner(course, %{name: "Learner"})
      _other = active_learner(course, %{name: "Other"})

      {:ok, message} = Channels.post_message(author, channel, "hey @all")

      assert message.mentioned_user_ids == []
    end
  end

  describe "delete_message/2" do
    setup do
      {course, _lecture} = course_with_lecture()
      channel = channel_fixture(course)
      author = active_learner(course, %{name: "Author"})
      {:ok, message} = Channels.post_message(author, channel, "my message")
      %{course: course, channel: channel, author: author, message: message}
    end

    test "the author can delete their own message", %{author: author, message: message} do
      assert {:ok, deleted} = Channels.delete_message(author, message)
      assert deleted.deleted_at
      assert deleted.deleted_by_id == author.id
    end

    test "an admin can delete anyone's message", %{message: message} do
      assert {:ok, deleted} = Channels.delete_message(admin_fixture(), message)
      assert deleted.deleted_at
    end

    test "another learner cannot delete someone else's message", %{
      course: course,
      message: message
    } do
      assert Channels.delete_message(active_learner(course), message) == {:error, :forbidden}
    end

    test "once archived, only an admin can delete", %{
      course: course,
      author: author,
      message: message
    } do
      {:ok, _} = Wasomi.Catalog.archive_course(course)

      assert Channels.delete_message(author, message) == {:error, :forbidden}
      assert {:ok, _} = Channels.delete_message(admin_fixture(), message)
    end
  end

  describe "unread tracking" do
    setup do
      {course, _lecture} = course_with_lecture()
      channel = channel_fixture(course)
      %{course: course, channel: channel}
    end

    test "counts others' live messages after the last read marker", %{
      course: course,
      channel: channel
    } do
      reader = active_learner(course, %{name: "Reader"})
      other = active_learner(course, %{name: "Other"})

      channel_message_fixture(channel, other, body: "one")
      channel_message_fixture(channel, other, body: "two")
      channel_message_fixture(channel, reader, body: "mine")
      other_deleted = channel_message_fixture(channel, other, body: "oops")
      {:ok, _} = Channels.delete_message(admin_fixture(), other_deleted)

      # the reader's own message and the deleted one don't count
      assert Channels.unread_count(reader, channel) == 2

      Channels.mark_read(reader, channel)
      assert Channels.unread_count(reader, channel) == 0

      channel_message_fixture(channel, other, body: "three")
      assert Channels.unread_count(reader, channel) == 1
    end
  end

  describe "reactions" do
    setup do
      {course, _lecture} = course_with_lecture()
      channel = channel_fixture(course)
      author = active_learner(course, %{name: "Author"})
      {:ok, message} = Channels.post_message(author, channel, "react to me")
      %{course: course, channel: channel, message: message}
    end

    test "toggles a reaction on and off", %{course: course, message: message} do
      reader = active_learner(course, %{name: "Reader"})

      assert {:ok, _} = Channels.toggle_reaction(reader, message, "👍")
      groups = Channels.group_reactions(Channels.get_message(message.id).reactions, reader.id)
      assert [%{emoji: "👍", count: 1, mine?: true}] = groups

      assert {:ok, _} = Channels.toggle_reaction(reader, message, "👍")
      assert Channels.group_reactions(Channels.get_message(message.id).reactions, reader.id) == []
    end

    test "counts one per user per emoji and groups most-used first", %{
      course: course,
      message: message
    } do
      a = active_learner(course, %{name: "Ada"})
      b = active_learner(course, %{name: "Ben"})

      Channels.toggle_reaction(a, message, "🎉")
      Channels.toggle_reaction(b, message, "🎉")
      Channels.toggle_reaction(a, message, "👍")

      groups = Channels.group_reactions(Channels.get_message(message.id).reactions, a.id)
      assert [%{emoji: "🎉", count: 2}, %{emoji: "👍", count: 1, mine?: true}] = groups
    end

    test "a non-member cannot react", %{message: message} do
      assert Channels.toggle_reaction(user_fixture(), message, "👍") == {:error, :forbidden}
    end

    test "an unsupported emoji is rejected", %{course: course, message: message} do
      reader = active_learner(course, %{name: "Reader"})
      assert Channels.toggle_reaction(reader, message, "🥔") == {:error, :forbidden}
    end
  end
end
