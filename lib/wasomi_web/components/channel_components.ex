defmodule WasomiWeb.ChannelComponents do
  @moduledoc """
  Presentational bits for course cohort channels.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import WasomiWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders a message author: avatar initial, display name and a role chip.

  The name is plain text for now. When learner public profiles ship, this is
  the single place that turns into a link (respecting the author's
  public/private setting) — callers already route every author through here.
  """
  attr :user, :map, default: nil
  attr :role, :atom, default: :active
  attr :class, :string, default: nil

  def channel_author(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-2", @class]}>
      <span class="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-mint text-xs font-semibold uppercase text-primary">
        {author_initial(@user)}
      </span>
      <span class="text-sm font-semibold text-ink">{author_name(@user)}</span>
      <span :if={@role == :admin} class={role_chip("bg-ink text-white")}>Wasomi</span>
      <span :if={@role == :alumni} class={role_chip("bg-surface text-body")}>Alumni</span>
    </span>
    """
  end

  @doc """
  Renders a message body, turning `@[Name](user:42)` mention tokens and
  `@all` / `@everyone` into highlighted spans — amber when the token points
  at the reader, brand colour otherwise.
  """
  attr :body, :string, required: true
  attr :current_user_id, :any, default: nil

  def channel_body(assigns) do
    assigns = assign(assigns, :rendered, render_body(assigns.body, assigns.current_user_id))

    ~H"""
    <p class="whitespace-pre-wrap break-words text-sm leading-relaxed text-body">{@rendered}</p>
    """
  end

  @doc "Reaction pills plus a click-to-open emoji picker for one message."
  attr :message, :map, required: true
  attr :groups, :list, required: true
  attr :emojis, :list, required: true

  def channel_reactions(assigns) do
    assigns = assign(assigns, :picker_id, "reaction-picker-#{assigns.message.id}")

    ~H"""
    <div class="mt-1.5 flex flex-wrap items-center gap-1.5 pl-9">
      <button
        :for={group <- @groups}
        type="button"
        phx-click="react"
        phx-value-id={@message.id}
        phx-value-emoji={group.emoji}
        class={[
          "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs transition",
          group.mine? && "border-primary/40 bg-mint text-primary",
          !group.mine? && "border-black/10 text-body hover:border-primary/40"
        ]}
      >
        <span>{group.emoji}</span>
        <span class="font-semibold">{group.count}</span>
      </button>

      <div class="relative">
        <button
          type="button"
          phx-click={JS.toggle(to: "##{@picker_id}", display: "flex")}
          class={[
            "grid h-6 w-6 place-items-center rounded-full text-muted transition hover:bg-mint hover:text-primary",
            @groups == [] && "opacity-0 group-hover:opacity-100"
          ]}
          aria-label="Add reaction"
        >
          <.icon name="hero-face-smile" class="h-4 w-4" />
        </button>
        <div
          id={@picker_id}
          phx-click-away={JS.hide(to: "##{@picker_id}")}
          class="absolute bottom-full left-0 z-10 mb-1 hidden gap-0.5 rounded-xl border border-black/10 bg-white p-1 shadow-lg"
        >
          <button
            :for={emoji <- @emojis}
            type="button"
            phx-click={
              JS.hide(to: "##{@picker_id}")
              |> JS.push("react", value: %{id: @message.id, emoji: emoji})
            }
            class="grid h-7 w-7 place-items-center rounded-lg text-base transition hover:bg-mint"
          >
            {emoji}
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc "Slide-down panel listing every channel member, with search."
  attr :members, :list, required: true
  attr :query, :string, default: ""
  attr :total, :integer, required: true
  attr :current_user_id, :any, default: nil
  attr :can_post?, :boolean, default: true

  def members_panel(assigns) do
    ~H"""
    <div
      id="channel-members-panel"
      phx-click-away="close-members"
      class="absolute right-6 top-full z-20 mt-2 w-72 rounded-2xl border border-black/10 bg-white p-3 text-left shadow-xl"
    >
      <div class="flex items-center justify-between px-1 pb-2">
        <p class="text-xs font-semibold uppercase tracking-wide text-muted">
          {@total} {if @total == 1, do: "member", else: "members"}
        </p>
        <button type="button" phx-click="close-members" class="text-muted hover:text-ink">
          <.icon name="hero-x-mark" class="h-4 w-4" />
        </button>
      </div>
      <form phx-change="search-members" class="mb-2">
        <input
          type="text"
          name="q"
          value={@query}
          placeholder="Search members"
          autocomplete="off"
          phx-debounce="150"
          class="w-full rounded-xl border border-black/10 px-3 py-1.5 text-sm text-ink focus:border-primary focus:outline-none focus:ring-0"
        />
      </form>
      <ul class="max-h-72 space-y-0.5 overflow-y-auto">
        <li
          :for={member <- @members}
          class="flex items-center gap-2 rounded-xl px-2 py-1.5 hover:bg-mint/50"
        >
          <span class="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-mint text-xs font-semibold uppercase text-primary">
            {author_name(member.user) |> String.first()}
          </span>
          <span class="min-w-0 flex-1 truncate text-sm text-ink">{author_name(member.user)}</span>
          <span :if={member.role == :admin} class={role_chip("bg-ink text-white")}>Wasomi</span>
          <span :if={member.role == :alumni} class={role_chip("bg-surface text-body")}>Alumni</span>
          <button
            :if={@can_post? and member.role != :admin and member.user.id != @current_user_id}
            type="button"
            phx-click="mention-member"
            phx-value-id={member.user.id}
            class="shrink-0 rounded-full px-2 py-0.5 text-sm font-bold text-primary hover:bg-mint"
            title={"Mention #{author_name(member.user)}"}
          >
            @
          </button>
        </li>
        <li :if={@members == []} class="px-2 py-6 text-center text-sm text-muted">
          No members found.
        </li>
      </ul>
    </div>
    """
  end

  def author_name(%{name: name}) when is_binary(name) and name != "", do: name
  def author_name(%{email: email}) when is_binary(email), do: email
  def author_name(_), do: "Former learner"

  defp author_initial(user), do: user |> author_name() |> String.first() |> to_string()

  defp role_chip(extra),
    do: "rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide " <> extra

  @mention_token ~r/@\[([^\]\n]+)\]\(user:(\d+)\)/
  @all_mention ~r/(^|\s)@(all|everyone)\b/i

  defp render_body(body, current_user_id) when is_binary(body) do
    body
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> replace_mention_tokens(current_user_id)
    |> replace_all_mention()
    |> Phoenix.HTML.raw()
  end

  defp render_body(body, _current_user_id), do: body

  defp replace_mention_tokens(text, current_user_id) do
    Regex.replace(@mention_token, text, fn _full, name, id ->
      mine? = to_string(current_user_id) == id
      mention_span("@" <> name, mine?)
    end)
  end

  defp replace_all_mention(text) do
    Regex.replace(@all_mention, text, fn _full, lead, word ->
      lead <> mention_span("@" <> word, false)
    end)
  end

  defp mention_span(label, true),
    do: ~s(<span class="rounded bg-amber-100 px-1 font-medium text-amber-900">#{label}</span>)

  defp mention_span(label, false),
    do: ~s(<span class="rounded bg-mint px-1 font-medium text-primary">#{label}</span>)
end
