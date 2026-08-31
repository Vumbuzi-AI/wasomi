defmodule WasomiWeb.ChannelLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Channels

  defp published_course_with_lecture do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    lecture_fixture(module_id: module.id, title: "Lesson one")
    Wasomi.Catalog.get_course_by_slug!(course.slug)
  end

  defp enrol!(user, course) do
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)
  end

  defp channel(view), do: find_live_child(view, "course-channel")

  describe "as an enrolled learner" do
    setup %{conn: conn} do
      user = user_fixture(%{name: "Amara"})
      course = published_course_with_lecture()
      enrol!(user, course)
      %{conn: log_in_user(conn, user), user: user, course: course}
    end

    test "opens on the Discussion tab and can post a message", %{conn: conn, course: course} do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")

      panel = channel(view)
      assert has_element?(panel, "#course-channel-composer")
      assert render(panel) =~ "No messages yet"

      panel
      |> form("#course-channel-composer", message: %{body: "Hello cohort!"})
      |> render_submit()

      assert render(channel(view)) =~ "Hello cohort!"
    end

    test "can remove their own message", %{conn: conn, user: user, course: course} do
      chan = Channels.get_or_create_for_course(course)
      {:ok, _} = Channels.post_message(user, chan, "delete me please")

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")
      panel = channel(view)

      assert render(panel) =~ "delete me please"

      panel |> element("button[phx-click='ask-delete']") |> render_click()
      assert has_element?(channel(view), "#channel-delete-modal")

      channel(view) |> element("#channel-delete-modal button", "Remove") |> render_click()

      assert render(channel(view)) =~ "Message removed"
    end

    test "does not show the announcement toggle", %{conn: conn, course: course} do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")

      refute render(channel(view)) =~ "Post as a pinned announcement"
    end

    test "renders a mention token as a highlighted @name", %{
      conn: conn,
      user: user,
      course: course
    } do
      chan = Channels.get_or_create_for_course(course)
      other = user_fixture(%{name: "Zawadi"})
      enrol!(other, course)
      {:ok, _} = Channels.post_message(user, chan, "welcome @[Zawadi](user:#{other.id})")

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")
      html = render(channel(view))

      assert html =~
               ~s(<span class="rounded bg-mint px-1 font-medium text-primary">@Zawadi</span>)

      refute html =~ "user:#{other.id}"
    end

    test "can react to a message and toggle it off", %{conn: conn, user: user, course: course} do
      chan = Channels.get_or_create_for_course(course)
      {:ok, message} = Channels.post_message(user, chan, "rate this")

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")

      channel(view)
      |> element("#reaction-picker-#{message.id} button", "🎉")
      |> render_click()

      assert Channels.group_reactions(Channels.get_message(message.id).reactions, user.id) ==
               [%{emoji: "🎉", count: 1, mine?: true}]

      # the pill renders without a reload
      assert has_element?(
               channel(view),
               ~s(button[phx-click="react"][phx-value-emoji="🎉"] span),
               "1"
             )
    end

    test "a reaction from another member appears without a reload", %{
      conn: conn,
      user: user,
      course: course
    } do
      chan = Channels.get_or_create_for_course(course)
      {:ok, message} = Channels.post_message(user, chan, "rate this too")

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")

      other = user_fixture(%{name: "Otieno"})
      enrol!(other, course)
      {:ok, _} = Channels.toggle_reaction(other, message, "🔥")

      assert render(channel(view)) =~ "🔥"
    end

    test "typing in the composer broadcasts a typing ping", %{
      conn: conn,
      course: course
    } do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")
      Channels.subscribe(Channels.get_or_create_for_course(course))

      channel(view) |> element("#course-channel-input") |> render_keyup(%{"key" => "a"})

      assert_receive {:typing, %{name: "Amara", typing: true}}
    end

    test "the members panel lists and searches members", %{conn: conn, course: course} do
      other = user_fixture(%{name: "Zawadi Mwangi"})
      enrol!(other, course)

      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")
      panel = channel(view)

      panel |> element("button[phx-click='toggle-members']") |> render_click()
      assert has_element?(panel, "#channel-members-panel")
      assert render(panel) =~ "Zawadi Mwangi" or render(panel) =~ "Zawadi"

      panel
      |> form("#channel-members-panel form", %{q: "zawadi"})
      |> render_change()

      html = render(channel(view))
      assert html =~ "Zawadi"
      refute html =~ ">Amara<"
    end

    test "another member's message streams in without a reload", %{conn: conn, course: course} do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")

      other = user_fixture(%{name: "Otieno"})
      enrol!(other, course)
      chan = Channels.get_or_create_for_course(course)
      {:ok, _} = Channels.post_message(other, chan, "hello from another tab")

      assert render(channel(view)) =~ "hello from another tab"
    end

    test "another member's typing shows a label", %{conn: conn, course: course} do
      {:ok, view, _html} = live(conn, ~p"/learn/courses/#{course.slug}?tab=discussion")

      other = user_fixture(%{name: "Otieno"})
      enrol!(other, course)
      chan = Channels.get_or_create_for_course(course)
      Channels.broadcast_typing(chan, other, true)

      assert render(channel(view)) =~ "Otieno is typing"
    end
  end

  test "an archived course channel is read-only", %{conn: conn} do
    user = user_fixture()
    course = published_course_with_lecture()
    enrol!(user, course)
    {:ok, _} = Wasomi.Catalog.archive_course(course)

    {:ok, view, _html} =
      live(log_in_user(conn, user), ~p"/learn/courses/#{course.slug}?tab=discussion")

    panel = channel(view)
    assert render(panel) =~ "the channel is read-only"
    refute has_element?(panel, "#course-channel-composer")
  end

  test "an admin can post a pinned announcement from the preview route", %{conn: conn} do
    {:ok, admin} = user_fixture() |> Wasomi.Accounts.update_user_role(:admin)
    course = published_course_with_lecture()
    learner = user_fixture(%{name: "Baraka"})
    enrol!(learner, course)

    {:ok, view, _html} =
      live(log_in_user(conn, admin), ~p"/admin/courses/#{course.slug}/preview?tab=discussion")

    panel = channel(view)
    assert render(panel) =~ "Post as a pinned announcement"

    panel
    |> form("#course-channel-composer", message: %{body: "Cohort kick-off is Monday"})
    |> render_submit()

    # toggle the announcement checkbox, then post
    panel |> element("input[type='checkbox']") |> render_click()

    panel
    |> form("#course-channel-composer", message: %{body: "Certificates go out Friday"})
    |> render_submit()

    chan = Channels.get_or_create_for_course(course)
    assert [pinned] = Channels.pinned_messages(chan)
    assert pinned.body == "Certificates go out Friday"
  end
end
