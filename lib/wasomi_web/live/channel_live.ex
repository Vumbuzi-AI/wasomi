defmodule WasomiWeb.ChannelLive do
  @moduledoc """
  Router-free discussion panel for a course cohort channel.

  Mounted by `WasomiWeb.CoursePlayerLive` via `live_render/3` when the
  learner opens the "Discussion" tab. Owns its own PubSub subscription so
  new messages stream in live without the parent player having to relay them.
  """
  use WasomiWeb, :live_view

  import WasomiWeb.ChannelComponents

  alias Phoenix.Socket.Broadcast
  alias Wasomi.{Accounts, Catalog, Channels}
  alias Wasomi.Channels.Message
  alias WasomiWeb.Presence

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns[:current_user] || Accounts.get_user!(session["current_user_id"])
    course = Catalog.get_course_by_slug!(session["course_slug"])
    channel = Channels.get_or_create_for_course(course)
    role = Channels.member_role(user, course)

    if connected?(socket) and role do
      Channels.subscribe(channel)

      Presence.track(self(), Channels.topic(channel), to_string(user.id), %{
        name: user.name || user.email
      })
    end

    socket =
      socket
      |> assign(:current_user, user)
      |> assign(:course, course)
      |> assign(:channel, channel)
      |> assign(:role, role)
      |> assign(:read_only?, Channels.read_only?(course))
      |> assign(:admin?, role == :admin)
      |> assign(:members, Channels.list_members(course))
      |> then(fn s -> assign(s, :member_count, length(s.assigns.members)) end)
      |> then(fn s ->
        assign(
          s,
          :mention_options,
          mention_options(s.assigns.members, user.id, role == :admin)
        )
      end)
      |> assign(:online_count, online_count(channel))
      |> assign(:reaction_emojis, Channels.reaction_emojis())
      |> assign(:message_emojis, Channels.message_emojis())
      |> assign(:typing_users, %{})
      |> assign(:show_members, false)
      |> assign(:member_query, "")
      |> assign(:show_pins, false)
      |> assign(:as_announcement, false)
      |> assign(:has_more?, false)
      |> assign(:deleting_message, nil)

    socket =
      if role do
        messages = Channels.list_messages(channel)
        if connected?(socket), do: Channels.mark_read(user, channel)

        pinned = Channels.pinned_messages(channel)

        socket
        |> assign(:pinned, pinned)
        |> assign(:show_pins, length(pinned) <= 1)
        |> assign(:has_more?, length(messages) >= 50)
        |> assign(:oldest_at, oldest_at(messages))
        |> stream(:messages, messages)
      else
        socket
        |> assign(:pinned, [])
        |> assign(:oldest_at, nil)
        |> stream(:messages, [])
      end

    socket =
      case session["highlight_message_id"] do
        id when is_binary(id) and id != "" and role != nil ->
          push_event(socket, "channel:highlight", %{id: id})

        _ ->
          socket
      end

    # Nested LiveView: render only the panel, never the learner app layout
    # (its `#flash-group` / `#client-error` ids would collide with the
    # parent player's and break DOM patching for this view).
    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("typing", _params, socket) do
    if not is_nil(socket.assigns.role) and not socket.assigns.read_only? do
      Channels.broadcast_typing(socket.assigns.channel, socket.assigns.current_user, true)
    end

    {:noreply, socket}
  end

  def handle_event("toggle-members", _params, socket) do
    {:noreply, socket |> update(:show_members, &(not &1)) |> assign(:member_query, "")}
  end

  def handle_event("close-members", _params, socket) do
    {:noreply, assign(socket, :show_members, false)}
  end

  def handle_event("search-members", %{"q" => query}, socket) do
    {:noreply, assign(socket, :member_query, query)}
  end

  def handle_event("mention-member", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.members, &(to_string(&1.user.id) == to_string(id))) do
      %{user: user} ->
        {:noreply,
         socket
         |> assign(:show_members, false)
         |> push_event("channel:insert-mention", %{id: user.id, name: user.name || user.email})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("send", %{"message" => %{"body" => body}}, socket) do
    %{current_user: user, channel: channel} = socket.assigns
    announcement? = socket.assigns.admin? and socket.assigns.as_announcement

    result =
      if announcement?,
        do: Channels.post_announcement(user, channel, body),
        else: Channels.post_message(user, channel, body)

    case result do
      {:ok, message} ->
        Channels.broadcast_typing(channel, user, false)

        {:noreply,
         socket
         |> assign(:as_announcement, false)
         |> push_event("channel:reset-composer", %{})
         |> apply_message(message)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can't post in this channel.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Your message couldn't be posted.")}
    end
  end

  def handle_event("toggle-announcement", _params, socket) do
    {:noreply, assign(socket, :as_announcement, not socket.assigns.as_announcement)}
  end

  def handle_event("toggle-pins", _params, socket) do
    {:noreply, update(socket, :show_pins, &(not &1))}
  end

  def handle_event("react", %{"id" => id, "emoji" => emoji}, socket) do
    with %Message{} = message <- Channels.get_message(id),
         {:ok, _} <- Channels.toggle_reaction(socket.assigns.current_user, message, emoji) do
      {:noreply, refresh_message(socket, id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("ask-delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_message, Channels.get_message(id))}
  end

  def handle_event("cancel-delete", _params, socket) do
    {:noreply, assign(socket, :deleting_message, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket = assign(socket, :deleting_message, nil)

    with %Message{} = message <- Channels.get_message(id),
         {:ok, _} <- Channels.delete_message(socket.assigns.current_user, message) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "You can't remove that message.")}
    end
  end

  def handle_event("pin", %{"id" => id}, socket), do: pin(socket, id, &Channels.pin_message/2)
  def handle_event("unpin", %{"id" => id}, socket), do: pin(socket, id, &Channels.unpin_message/2)

  def handle_event("load-earlier", _params, socket) do
    %{channel: channel, oldest_at: oldest_at} = socket.assigns

    case oldest_at do
      nil ->
        {:noreply, socket}

      before ->
        earlier = Channels.list_messages(channel, before: before)

        socket =
          Enum.reduce(earlier, socket, fn message, acc ->
            stream_insert(acc, :messages, message, at: 0)
          end)

        {:noreply,
         socket
         |> assign(:has_more?, length(earlier) >= 50)
         |> assign(:oldest_at, oldest_at(earlier) || before)}
    end
  end

  @impl true
  def handle_info(%Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :online_count, online_count(socket.assigns.channel))}
  end

  def handle_info({:message_created, message}, socket) do
    if connected?(socket) and not is_nil(socket.assigns.role) and
         message.user_id != socket.assigns.current_user.id do
      Channels.mark_read(socket.assigns.current_user, socket.assigns.channel)
    end

    {:noreply, apply_message(socket, message)}
  end

  def handle_info({:message_deleted, id}, socket) do
    case Channels.get_message(id) do
      %Message{} = message ->
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:pinned, Channels.pinned_messages(socket.assigns.channel))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:message_updated, message}, socket) do
    {:noreply,
     socket
     |> stream_insert(:messages, message)
     |> assign(:pinned, Channels.pinned_messages(socket.assigns.channel))}
  end

  def handle_info({:message_reacted, id}, socket) do
    case Channels.get_message(id) do
      %Message{} = message -> {:noreply, stream_insert(socket, :messages, message)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:typing, %{user_id: user_id}}, socket)
      when user_id == socket.assigns.current_user.id do
    {:noreply, socket}
  end

  def handle_info({:typing, %{user_id: user_id, name: name, typing: true}}, socket) do
    expires_at = System.monotonic_time(:millisecond) + 2_500
    Process.send_after(self(), {:clear_typing, user_id, expires_at}, 2_600)

    {:noreply,
     update(socket, :typing_users, &Map.put(&1, user_id, %{name: name, expires_at: expires_at}))}
  end

  def handle_info({:typing, %{user_id: user_id}}, socket) do
    {:noreply, update(socket, :typing_users, &Map.delete(&1, user_id))}
  end

  def handle_info({:clear_typing, user_id, expires_at}, socket) do
    typing_users =
      case socket.assigns.typing_users do
        %{^user_id => %{expires_at: ^expires_at}} = map -> Map.delete(map, user_id)
        map -> map
      end

    {:noreply, assign(socket, :typing_users, typing_users)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp apply_message(socket, %Message{} = message) do
    socket =
      socket
      |> stream_insert(:messages, message)
      |> update(:typing_users, &Map.delete(&1, message.user_id))

    if message.kind == :announcement do
      assign(socket, :pinned, Channels.pinned_messages(socket.assigns.channel))
    else
      socket
    end
  end

  defp refresh_message(socket, id) do
    case Channels.get_message(id) do
      %Message{} = message -> stream_insert(socket, :messages, message)
      _ -> socket
    end
  end

  defp filtered_members(members, query) do
    q = query |> to_string() |> String.trim() |> String.downcase()

    if q == "" do
      members
    else
      Enum.filter(members, fn %{user: user} ->
        String.contains?(String.downcase(author_name(user)), q)
      end)
    end
  end

  defp pin(socket, id, fun) do
    with %Message{} = message <- Channels.get_message(id),
         {:ok, _} <- fun.(socket.assigns.current_user, message) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "That didn't work.")}
    end
  end

  defp online_count(channel) do
    channel |> Channels.topic() |> Presence.list() |> map_size()
  end

  defp oldest_at([]), do: nil

  defp oldest_at(messages) do
    messages
    |> Enum.map(& &1.inserted_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(DateTime, fn -> nil end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="course-channel-panel" class="flex flex-col">
      <%= if @role do %>
        <div class="relative flex items-center justify-between gap-3 border-b border-black/5 px-6 py-4">
          <div class="flex min-w-0 items-center gap-3">
            <span class="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-mint text-primary">
              <.icon name="hero-chat-bubble-left-right" class="h-5 w-5" />
            </span>
            <div class="min-w-0">
              <p class="text-sm font-semibold text-ink">Cohort discussion</p>
              <p class="truncate text-xs text-muted">{@course.title}</p>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-2.5 text-xs text-muted">
            <span :if={@online_count > 0} class="flex items-center gap-1.5 whitespace-nowrap">
              <span class="h-1.5 w-1.5 rounded-full bg-green-500"></span>
              {@online_count} online
            </span>
            <button
              type="button"
              phx-click="toggle-members"
              class={[
                "flex items-center gap-2 rounded-full border px-2 py-1 transition",
                @show_members && "border-primary/40 bg-mint text-primary",
                !@show_members && "border-black/10 hover:border-primary/40"
              ]}
            >
              <span class="flex -space-x-2">
                <span
                  :for={member <- Enum.take(@members, 3)}
                  class="grid h-6 w-6 place-items-center rounded-full bg-secondary/10 text-[10px] font-semibold uppercase text-secondary ring-2 ring-white"
                >
                  {member_initial(member)}
                </span>
              </span>
              <span class="font-medium">{@member_count}</span>
              <.icon name="hero-chevron-down" class="h-3.5 w-3.5" />
            </button>
          </div>

          <.members_panel
            :if={@show_members}
            members={filtered_members(@members, @member_query)}
            query={@member_query}
            total={@member_count}
            current_user_id={@current_user.id}
            can_post?={not @read_only?}
          />
        </div>

        <div :if={@pinned != []} class="border-b border-black/5 bg-mint/40 px-6 py-3">
          <button
            type="button"
            phx-click="toggle-pins"
            class="flex w-full items-center justify-between text-xs font-semibold uppercase tracking-wide text-primary"
          >
            <span class="flex items-center gap-1.5">
              <.icon name="hero-megaphone" class="h-4 w-4" />
              {length(@pinned)} pinned {if length(@pinned) == 1, do: "message", else: "messages"}
            </span>
            <.icon
              name={if @show_pins, do: "hero-chevron-up", else: "hero-chevron-down"}
              class="h-4 w-4"
            />
          </button>
          <ul :if={@show_pins} class="mt-2 space-y-2">
            <li :for={message <- @pinned} class="rounded-2xl bg-white px-4 py-3 shadow-sm">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <.channel_author user={message.user} role={:admin} />
                  <.channel_body body={message.body} current_user_id={@current_user.id} />
                </div>
                <button
                  :if={@admin?}
                  type="button"
                  phx-click="unpin"
                  phx-value-id={message.id}
                  class="shrink-0 rounded-full px-2 py-1 text-xs font-semibold text-muted hover:text-primary"
                >
                  Unpin
                </button>
              </div>
            </li>
          </ul>
        </div>

        <div
          id="course-channel-scroll"
          phx-hook="ChannelScroll"
          class="h-[26rem] overflow-y-auto px-6 py-5"
        >
          <div :if={@has_more?} class="mb-4 text-center">
            <button
              type="button"
              phx-click="load-earlier"
              class="rounded-full border border-black/10 bg-white px-4 py-1.5 text-xs font-semibold text-body transition hover:border-primary hover:text-primary"
            >
              Load earlier messages
            </button>
          </div>

          <div id="course-channel-messages" phx-update="stream" class="flex min-h-full flex-col gap-4">
            <div
              id="course-channel-empty"
              class="hidden text-center only:flex only:flex-1 only:flex-col only:items-center only:justify-center"
            >
              <span class="grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
                <.icon name="hero-chat-bubble-oval-left-ellipsis" class="h-7 w-7" />
              </span>
              <h3 class="mt-4 text-base font-semibold text-ink">No messages yet</h3>
              <p class="mt-1 max-w-sm text-sm text-body">
                This channel is for your cohort and the Wasomi course team. Say hello,
                ask a question, or share what you're working on.
              </p>
              <p class="mt-3 max-w-sm text-xs text-muted">
                Mention someone with @ · announcements from the team stay pinned up top
              </p>
            </div>
            <div :for={{dom_id, message} <- @streams.messages} id={dom_id} class="group flex flex-col">
              <div class="flex items-center justify-between gap-3">
                <.channel_author user={message.user} role={author_role(message, @members)} />
                <div class="flex items-center gap-2">
                  <time class="text-[11px] text-muted">{short_time(message.inserted_at)}</time>
                  <button
                    :if={can_pin?(assigns, message)}
                    type="button"
                    phx-click="pin"
                    phx-value-id={message.id}
                    class="hidden rounded-full px-2 py-0.5 text-[11px] font-semibold text-muted hover:text-primary group-hover:inline"
                  >
                    Pin
                  </button>
                  <button
                    :if={can_delete?(assigns, message)}
                    type="button"
                    phx-click="ask-delete"
                    phx-value-id={message.id}
                    class="hidden rounded-full px-2 py-0.5 text-[11px] font-semibold text-muted hover:text-rose-600 group-hover:inline"
                  >
                    Remove
                  </button>
                </div>
              </div>
              <div class="mt-1 pl-9">
                <p :if={message.deleted_at} class="text-sm italic text-muted">
                  Message removed
                </p>
                <.channel_body
                  :if={!message.deleted_at}
                  body={message.body}
                  current_user_id={@current_user.id}
                />
              </div>
              <.channel_reactions
                :if={!message.deleted_at}
                message={message}
                groups={Channels.group_reactions(message.reactions, @current_user.id)}
                emojis={@reaction_emojis}
              />
            </div>
          </div>
        </div>

        <p :if={typing_label(@typing_users)} class="px-6 pb-1 pt-2 text-xs italic text-muted">
          {typing_label(@typing_users)}
        </p>

        <div class="border-t border-black/5 bg-white px-6 py-4">
          <p :if={@read_only?} class="text-sm text-muted">
            This course is archived — the channel is read-only.
          </p>

          <form
            :if={!@read_only?}
            id="course-channel-composer"
            phx-submit="send"
            phx-hook="ChannelComposer"
            data-mention-users={Jason.encode!(@mention_options)}
          >
            <div class="flex items-end gap-2">
              <textarea
                id="course-channel-input"
                name="message[body]"
                rows="1"
                maxlength="4000"
                phx-keyup="typing"
                phx-throttle="1200"
                phx-update="ignore"
                placeholder={
                  if @admin?,
                    do: "Write a message… @name to mention, @all for everyone",
                    else: "Write a message… use @ to mention someone"
                }
                class="h-11 max-h-32 min-h-[2.75rem] flex-1 resize-none rounded-2xl border border-black/10 px-4 py-2.5 text-sm leading-6 text-ink focus:border-primary focus:outline-none focus:ring-0"
              ></textarea>

              <div class="relative flex h-11 shrink-0 items-center">
                <button
                  type="button"
                  phx-click={JS.toggle(to: "#composer-emoji-picker", display: "grid")}
                  class="grid h-9 w-9 place-items-center rounded-full text-muted transition hover:bg-mint hover:text-primary"
                  aria-label="Insert emoji"
                >
                  <.icon name="hero-face-smile" class="h-5 w-5" />
                </button>
                <div
                  id="composer-emoji-picker"
                  phx-click-away={JS.hide(to: "#composer-emoji-picker")}
                  class="absolute bottom-full right-0 z-20 mb-2 hidden w-[17rem] grid-cols-8 gap-0.5 rounded-2xl border border-black/10 bg-white p-2 shadow-xl"
                >
                  <button
                    :for={emoji <- @message_emojis}
                    type="button"
                    phx-click={
                      JS.dispatch("wasomi:insert-emoji",
                        to: "#course-channel-input",
                        detail: %{emoji: emoji}
                      )
                    }
                    class="grid h-7 w-7 place-items-center rounded-lg text-lg transition hover:bg-mint"
                  >
                    {emoji}
                  </button>
                </div>
              </div>

              <button
                type="submit"
                class="inline-flex h-11 shrink-0 items-center rounded-full bg-primary px-5 text-sm font-semibold text-white transition hover:bg-ink"
              >
                Send
              </button>
            </div>
            <label
              :if={@admin?}
              class="mt-2 inline-flex items-center gap-2 text-xs font-medium text-body"
            >
              <input
                type="checkbox"
                checked={@as_announcement}
                phx-click="toggle-announcement"
                class="h-3.5 w-3.5 rounded border-black/20 text-primary focus:ring-primary/30"
              /> Post as a pinned announcement (notifies active learners)
            </label>
          </form>
        </div>

        <.confirm_modal
          :if={@deleting_message}
          id="channel-delete-modal"
          title="Remove this message?"
          confirm_label="Remove"
          confirm={JS.push("delete", value: %{id: @deleting_message.id})}
          cancel={JS.push("cancel-delete")}
        >
          The message will be replaced with "Message removed". This can't be undone.
        </.confirm_modal>
      <% else %>
        <div class="grid flex-1 place-items-center px-6 py-16 text-center">
          <div>
            <span class="mx-auto grid h-12 w-12 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-lock-closed" class="h-6 w-6" />
            </span>
            <p class="mt-4 text-sm text-body">
              The course channel is open to enrolled learners.
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp mention_options([], _self_id, _admin?), do: []

  defp mention_options(members, self_id, admin?) do
    people =
      members
      |> Enum.reject(&(&1.user.id == self_id))
      |> Enum.map(fn %{user: u} -> %{id: u.id, name: u.name || u.email} end)
      |> Enum.reject(&(is_nil(&1.name) or &1.name == ""))

    if admin?, do: [%{id: "all", name: "all"} | people], else: people
  end

  defp typing_label(typing_users) when map_size(typing_users) == 0, do: nil

  defp typing_label(typing_users) do
    names = typing_users |> Map.values() |> Enum.map(& &1.name) |> Enum.uniq()

    case names do
      [one] -> "#{one} is typing…"
      [one, two] -> "#{one} and #{two} are typing…"
      _ -> "Several people are typing…"
    end
  end

  defp member_initial(%{user: user}), do: user |> author_name() |> String.first() |> to_string()

  defp author_role(%{user_id: nil}, _members), do: :active

  defp author_role(%{user_id: user_id}, members) do
    case Enum.find(members, &(&1.user.id == user_id)) do
      %{role: role} -> role
      _ -> :active
    end
  end

  defp can_delete?(assigns, message) do
    is_nil(message.deleted_at) and not assigns.read_only? and
      (assigns.admin? or message.user_id == assigns.current_user.id)
  end

  defp can_pin?(assigns, message) do
    assigns.admin? and is_nil(message.deleted_at) and is_nil(message.pinned_at)
  end

  defp short_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %-I:%M %p")
  defp short_time(_), do: ""
end
