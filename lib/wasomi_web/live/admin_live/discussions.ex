defmodule WasomiWeb.AdminLive.Discussions do
  @moduledoc """
  Admin hub for every course cohort channel — pick a course on the left,
  chat and moderate on the right without going through the course preview.
  """
  use WasomiWeb, :live_view

  alias Wasomi.Channels

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Discussions")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    admin = socket.assigns.current_user
    search = params["q"] || ""
    rows = Channels.admin_channel_list(admin)

    selected =
      case params["course"] do
        slug when is_binary(slug) and slug != "" ->
          Enum.find(rows, &(&1.course.slug == slug))

        _ ->
          nil
      end

    # Opening a channel clears its unread badge for this admin.
    rows =
      if selected do
        Channels.mark_read(admin, Channels.get_or_create_for_course(selected.course))
        Enum.map(rows, &if(&1.course.id == selected.course.id, do: %{&1 | unread: 0}, else: &1))
      else
        rows
      end

    {:noreply,
     socket
     |> assign(:rows, rows)
     |> assign(:search, search)
     |> assign(:selected, selected)
     |> assign(:highlight_msg, params["msg"])
     |> assign(:visible_rows, filter_rows(rows, search))}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: discussions_path(query, slug(socket.assigns.selected)))}
  end

  defp filter_rows(rows, ""), do: rows

  defp filter_rows(rows, query) do
    q = String.downcase(query)
    Enum.filter(rows, &String.contains?(String.downcase(&1.course.title), q))
  end

  defp slug(nil), do: nil
  defp slug(%{course: %{slug: slug}}), do: slug

  defp discussions_path(query, course_slug) do
    params =
      %{q: query, course: course_slug}
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    ~p"/admin/discussions?#{params}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:discussions} current_user={@current_user}>
      <div class="w-full space-y-5 px-5 py-8 lg:px-8">
        <.page_header title="Discussions">
          <:subtitle>Every course cohort channel in one place — chat and moderate here.</:subtitle>
        </.page_header>

        <div class="grid gap-5 lg:grid-cols-[340px_minmax(0,1fr)]">
          <div class="rounded-3xl border border-black/5 bg-white p-4 shadow-card">
            <form phx-change="search" class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted"
              />
              <input
                type="search"
                name="q"
                value={@search}
                placeholder="Search courses"
                autocomplete="off"
                phx-debounce="200"
                class="h-10 w-full rounded-2xl border border-black/10 pl-10 pr-3 text-sm text-ink placeholder:text-muted focus:border-primary focus:outline-none focus:ring-0"
              />
            </form>

            <ul class="mt-3 max-h-[70vh] space-y-1 overflow-y-auto">
              <li :for={row <- @visible_rows}>
                <.link
                  patch={discussions_path(@search, row.course.slug)}
                  class={[
                    "block rounded-2xl border px-3 py-2.5 transition",
                    @selected && @selected.course.id == row.course.id &&
                      "border-primary/40 bg-mint",
                    !(@selected && @selected.course.id == row.course.id) &&
                      "border-transparent hover:bg-surface"
                  ]}
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="min-w-0 truncate text-sm font-semibold text-ink">
                      {row.course.title}
                    </span>
                    <span
                      :if={row.unread > 0}
                      class="grid h-5 min-w-5 shrink-0 place-items-center rounded-full bg-primary px-1.5 text-[11px] font-bold text-white"
                    >
                      {min(row.unread, 99)}
                    </span>
                  </div>
                  <div class="mt-1 flex items-center gap-2 text-[11px] text-muted">
                    <span>{row.member_count} members</span>
                    <span>·</span>
                    <span>
                      {row.message_count} {ngettext("message", "messages", row.message_count)}
                    </span>
                    <span :if={row.read_only?} class="rounded bg-surface px-1 font-medium">
                      archived
                    </span>
                  </div>
                  <p :if={row.last_activity_at} class="mt-0.5 text-[11px] text-muted">
                    last active {format_time(row.last_activity_at)}
                  </p>
                </.link>
              </li>
              <li :if={@visible_rows == []} class="px-3 py-6 text-center text-sm text-muted">
                No courses match "{@search}".
              </li>
            </ul>
          </div>

          <div class="overflow-hidden rounded-3xl border border-black/5 bg-white shadow-card">
            <%= if @selected do %>
              {live_render(@socket, WasomiWeb.ChannelLive,
                id: "admin-channel-#{@selected.course.slug}",
                session: %{
                  "current_user_id" => @current_user.id,
                  "course_slug" => @selected.course.slug,
                  "highlight_message_id" => @highlight_msg
                }
              )}
            <% else %>
              <div class="grid min-h-[60vh] place-items-center px-6 text-center">
                <div>
                  <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
                    <.icon name="hero-chat-bubble-left-right" class="h-7 w-7" />
                  </span>
                  <h3 class="mt-4 text-base font-semibold text-ink">Pick a course</h3>
                  <p class="mt-1 text-sm text-body">
                    Select a channel on the left to read and reply.
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %-I:%M %p")
  defp format_time(_), do: "—"
end
