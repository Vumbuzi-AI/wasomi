defmodule WasomiWeb.StudentComponents do
  @moduledoc """
  Shared chrome for the authenticated learner area.

  `student_layout/1` renders the persistent sidebar navigation used across the
  internal student routes (dashboard, courses taken, certificates, account,
  the course player and checkout).
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Wasomi.Notifications

  import WasomiWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: WasomiWeb.Endpoint,
    router: WasomiWeb.Router,
    statics: WasomiWeb.static_paths()

  @nav_items [
    %{key: :dashboard, label: "Dashboard", icon: "hero-squares-2x2", path: "/dashboard"},
    %{key: :courses, label: "My courses", icon: "hero-academic-cap", path: "/courses-taken"},
    %{
      key: :discussions,
      label: "Discussions",
      icon: "hero-chat-bubble-left-right",
      path: "/discussions"
    },
    %{key: :certificates, label: "Certificates", icon: "hero-trophy", path: "/certificates"},
    %{key: :notifications, label: "Notifications", icon: "hero-bell", path: "/notifications"},
    %{key: :browse, label: "Browse catalog", icon: "hero-magnifying-glass", path: "/catalog"},
    %{key: :account, label: "Account", icon: "hero-cog-6-tooth", path: "/users/settings"}
  ]

  @doc """
  Wraps a learner page in the sidebar shell.

  ## Attributes

    * `:active` - the key of the active nav item (`:dashboard`, `:courses`,
      `:study`, `:certificates`, `:notifications`, `:browse`, `:account`).
      Defaults to `nil`.
    * `:current_user` - the signed-in user, used for the profile footer.
  """
  attr :active, :atom, default: nil
  attr :current_user, :map, required: true
  attr :embedded, :boolean, default: false
  attr :unread_notifications_count, :integer, default: nil
  slot :inner_block, required: true

  def student_layout(assigns) do
    assigns =
      assigns
      |> assign(:nav_items, @nav_items)
      |> assign(
        :unread_notifications_count,
        assigns[:unread_notifications_count] ||
          Notifications.count_unread_for_user(assigns.current_user)
      )

    ~H"""
    <div class="min-h-screen bg-surface text-ink lg:flex">
      <%!-- Mobile top bar --%>
      <div
        :if={!@embedded}
        class="flex items-center justify-between border-b border-black/5 bg-white px-5 py-4 lg:hidden"
      >
        <.link navigate={~p"/dashboard"} class="flex items-center">
          <img src={~p"/images/logo.png"} alt="Wasomi" class="h-7 w-auto" />
        </.link>
        <button
          type="button"
          phx-click={JS.toggle(to: "#student-sidebar")}
          class="grid h-10 w-10 place-items-center rounded-xl border border-black/10 text-ink"
        >
          <.icon name="hero-bars-3" class="h-5 w-5" />
        </button>
      </div>

      <%!-- Sidebar --%>
      <aside
        :if={!@embedded}
        id="student-sidebar"
        class="app-sidebar hidden w-full shrink-0 border-b border-black/5 bg-white lg:flex lg:h-screen lg:w-72 lg:flex-col lg:border-b-0 lg:border-r"
      >
        <div class="sidebar-header hidden items-center justify-between px-6 py-7 lg:flex">
          <.link navigate={~p"/dashboard"} class="sidebar-label flex items-center">
            <img src={~p"/images/logo.png"} alt="Wasomi" class="h-7 w-auto" />
          </.link>
          <button
            type="button"
            id="student-sidebar-toggle"
            phx-hook="SidebarToggle"
            class="grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-black/10 text-ink transition hover:border-primary hover:text-primary"
            title="Collapse sidebar"
          >
            <.icon name="hero-chevron-double-left" class="sidebar-toggle-icon h-4 w-4" />
          </button>
        </div>

        <nav class="flex-1 space-y-1 px-4 py-4 lg:py-2">
          <.nav_link
            :for={item <- @nav_items}
            item={item}
            active={@active}
            unread_notifications_count={@unread_notifications_count}
          />
        </nav>

        <div class="border-t border-black/5 p-4">
          <.link
            :if={@current_user.role == :admin}
            navigate={~p"/admin"}
            class="sidebar-row group relative mb-2 flex items-center gap-3 rounded-xl bg-ink px-3 py-2.5 text-sm font-medium text-white transition hover:bg-primary"
          >
            <.icon name="hero-chart-pie" class="h-5 w-5 shrink-0" />
            <span class="sidebar-label inline-block">Admin dashboard</span>
            <.sidebar_tooltip label="Admin dashboard" />
          </.link>
          <div class="sidebar-row group relative flex items-center gap-3 rounded-2xl bg-surface px-3 py-3">
            <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-mint font-semibold uppercase text-primary">
              {String.first(@current_user.name || @current_user.email)}
            </span>
            <div class="sidebar-label min-w-0">
              <p class="truncate text-sm font-semibold text-ink">
                {@current_user.name || "Learner"}
              </p>
              <p class="truncate text-xs text-muted">{@current_user.email}</p>
            </div>
            <.sidebar_tooltip label={@current_user.name || @current_user.email} />
          </div>
          <.link
            href={~p"/users/log_out"}
            method="delete"
            class="sidebar-row group relative mt-3 flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-body transition hover:bg-surface hover:text-primary"
          >
            <.icon name="hero-arrow-left-on-rectangle" class="h-5 w-5 shrink-0" />
            <span class="sidebar-label inline-block">Log out</span>
            <.sidebar_tooltip label="Log out" />
          </.link>
        </div>
      </aside>

      <%!-- Page content --%>
      <main class="min-w-0 flex-1 lg:h-screen lg:overflow-y-auto">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  @doc """
  Renders an enrolled-course card with thumbnail, progress and a resume action.

  Expects a `card` map with `:course`, `:progress`, `:resume_lecture` and
  `:started?` keys (see the learner LiveViews).

    * `:id` - DOM id for the card article.
    * `:progress_id` - optional DOM id for the live percentage badge.
  """
  attr :card, :map, required: true
  attr :id, :string, required: true
  attr :progress_id, :string, default: nil

  def course_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="group flex flex-col overflow-hidden rounded-3xl border border-black/5 bg-white shadow-card transition duration-300 hover:-translate-y-1 hover:shadow-card-hover"
    >
      <div class="relative aspect-[16/9] overflow-hidden bg-mint">
        <img
          src={@card.course.thumbnail_key}
          alt=""
          class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-ink/55 via-ink/10 to-transparent"></div>
        <span class="absolute left-4 top-4 rounded-full bg-white/95 px-3 py-1 text-xs font-semibold text-primary shadow-sm">
          {progress_label(@card)}
        </span>
        <span
          id={@progress_id}
          class="absolute right-4 top-4 rounded-full bg-ink/45 px-2.5 py-1 text-xs font-semibold text-white backdrop-blur-sm"
        >
          {@card.progress.percent}%
        </span>
      </div>

      <div class="flex flex-1 flex-col p-6">
        <h3 class="text-lg font-semibold leading-snug text-ink">{@card.course.title}</h3>
        <p :if={@card.resume_lecture} class="mt-2 flex items-start gap-1.5 text-sm text-body">
          <.icon name="hero-play-circle-mini" class="mt-0.5 h-4 w-4 shrink-0 text-primary" />
          <span class="line-clamp-1">Next: {@card.resume_lecture.title}</span>
        </p>
        <p :if={!@card.resume_lecture} class="mt-2 text-sm text-body">
          Course materials will appear here when lectures are added.
        </p>

        <div class="mt-auto pt-6">
          <div class="h-2 overflow-hidden rounded-full bg-mint">
            <div
              class="h-full rounded-full bg-primary transition-all duration-500"
              style={"width: #{@card.progress.percent}%"}
            >
            </div>
          </div>
          <p class="mt-2 text-xs text-muted">
            {@card.progress.completed} of {@card.progress.total} lectures completed
          </p>

          <.link
            navigate={course_destination(@card)}
            class="group/btn mt-5 flex items-center justify-between gap-2 rounded-full bg-ink py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
          >
            {course_action(@card)}
            <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover/btn:bg-ink">
              <.icon name="hero-arrow-right-mini" class="h-4 w-4" />
            </span>
          </.link>
        </div>
      </div>
    </article>
    """
  end

  defp progress_label(%{progress: %{complete?: true}}), do: "Completed"
  defp progress_label(%{started?: true}), do: "In progress"
  defp progress_label(_card), do: "Ready to start"

  defp course_action(%{progress: %{complete?: true}}), do: "Review course"
  defp course_action(%{started?: true}), do: "Continue learning"
  defp course_action(_card), do: "Start course"

  defp course_destination(%{resume_lecture: nil, course: course}), do: ~p"/courses/#{course.slug}"
  defp course_destination(%{course: course}), do: ~p"/learn/courses/#{course.slug}"

  attr :item, :map, required: true
  attr :active, :atom, required: true
  attr :unread_notifications_count, :integer, required: true

  defp nav_link(assigns) do
    assigns =
      assigns
      |> assign(:notifications_item?, assigns.item.key == :notifications)
      |> assign(:has_unread_notifications?, assigns.unread_notifications_count > 0)

    ~H"""
    <.link
      id={"student-nav-#{@item.key}"}
      navigate={@item.path}
      class={[
        "sidebar-row group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition",
        if(@item.key == @active,
          do: "bg-dark text-white shadow-sm",
          else: "text-body hover:bg-surface hover:text-primary"
        )
      ]}
    >
      <span class="relative grid shrink-0 place-items-center">
        <.icon name={@item.icon} class="h-5 w-5" />
        <span
          :if={@notifications_item? && @has_unread_notifications?}
          class="sidebar-notification-dot absolute -right-0.5 -top-0.5 hidden h-2.5 w-2.5 rounded-full bg-primary ring-2 ring-white"
        >
        </span>
        <span
          :if={@notifications_item? && @has_unread_notifications?}
          class="sidebar-notification-count absolute -right-2 -top-2 grid h-4 min-w-4 place-items-center rounded-full bg-primary px-1 text-[10px] font-bold leading-none text-white ring-2 ring-white"
        >
          {compact_count(@unread_notifications_count)}
        </span>
      </span>
      <span class="sidebar-label inline-block">
        {@item.label}
      </span>
      <.sidebar_tooltip label={nav_tooltip_label(@item, @unread_notifications_count)} />
    </.link>
    """
  end

  defp compact_count(count) when count > 9, do: "9+"
  defp compact_count(count), do: count

  defp nav_tooltip_label(%{key: :notifications, label: label}, count) when count > 0 do
    "#{label} (#{count} unread)"
  end

  defp nav_tooltip_label(%{label: label}, _count), do: label

  # Shown only while the sidebar is collapsed (see `.sidebar-tooltip` in
  # app.css) — a plain `title` attribute works too, but browsers impose a
  # multi-hundred-ms hover delay on those that can't be shortened from CSS,
  # so icon-only mode gets its own instant, always-fast tooltip instead.
  attr :label, :string, required: true

  defp sidebar_tooltip(assigns) do
    ~H"""
    <span class="sidebar-tooltip pointer-events-none absolute left-full top-1/2 z-50 ml-3 -translate-y-1/2 whitespace-nowrap rounded-lg bg-ink px-2.5 py-1.5 text-xs font-medium text-white shadow-lg">
      {@label}
    </span>
    """
  end
end
