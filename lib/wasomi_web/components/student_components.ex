defmodule WasomiWeb.StudentComponents do
  @moduledoc """
  Shared chrome for the authenticated learner area.

  `student_layout/1` renders the persistent sidebar navigation used across the
  internal student routes (dashboard, courses taken, certificates, account,
  the course player and checkout).
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import WasomiWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: WasomiWeb.Endpoint,
    router: WasomiWeb.Router,
    statics: WasomiWeb.static_paths()

  @nav_items [
    %{key: :dashboard, label: "Dashboard", icon: "hero-squares-2x2", path: "/dashboard"},
    %{key: :courses, label: "My courses", icon: "hero-academic-cap", path: "/courses-taken"},
    %{key: :certificates, label: "Certificates", icon: "hero-trophy", path: "/certificates"},
    %{key: :browse, label: "Browse catalog", icon: "hero-magnifying-glass", path: "/courses"},
    %{key: :account, label: "Account", icon: "hero-cog-6-tooth", path: "/users/settings"}
  ]

  @doc """
  Wraps a learner page in the sidebar shell.

  ## Attributes

    * `:active` - the key of the active nav item (`:dashboard`, `:courses`,
      `:certificates`, `:browse`, `:account`). Defaults to `nil`.
    * `:current_user` - the signed-in user, used for the profile footer.
  """
  attr :active, :atom, default: nil
  attr :current_user, :map, required: true
  slot :inner_block, required: true

  def student_layout(assigns) do
    assigns = assign(assigns, :nav_items, @nav_items)

    ~H"""
    <div class="min-h-screen bg-soft text-dark lg:flex">
      <%!-- Mobile top bar --%>
      <div class="flex items-center justify-between border-b border-black/5 bg-white px-5 py-4 lg:hidden">
        <.link navigate={~p"/dashboard"} class="flex items-center gap-3 font-bold text-dark">
          <span class="grid h-9 w-9 place-items-center rounded-[10px] bg-primary text-white">K</span>
          <span>Wasomi</span>
        </.link>
        <button
          type="button"
          phx-click={JS.toggle(to: "#student-sidebar")}
          class="grid h-10 w-10 place-items-center rounded-xl border border-black/10 text-dark"
        >
          <.icon name="hero-bars-3" class="h-5 w-5" />
        </button>
      </div>

      <%!-- Sidebar --%>
      <aside
        id="student-sidebar"
        class="hidden w-full shrink-0 border-b border-black/5 bg-white lg:flex lg:h-screen lg:w-72 lg:flex-col lg:border-b-0 lg:border-r"
      >
        <div class="hidden px-6 py-7 lg:block">
          <.link navigate={~p"/dashboard"} class="flex items-center gap-3 font-bold text-dark">
            <span class="grid h-10 w-10 place-items-center rounded-[10px] bg-primary text-white">
              K
            </span>
            <span class="text-lg">Wasomi</span>
          </.link>
        </div>

        <nav class="flex-1 space-y-1 px-4 py-4 lg:py-2">
          <.nav_link :for={item <- @nav_items} item={item} active={@active} />
        </nav>

        <div class="border-t border-black/5 p-4">
          <.link
            :if={@current_user.role == :admin}
            navigate={~p"/admin"}
            class="mb-2 flex items-center gap-3 rounded-xl bg-dark px-3 py-2.5 text-sm font-medium text-white transition hover:bg-primary"
          >
            <.icon name="hero-chart-pie" class="h-5 w-5" /> Admin dashboard
          </.link>
          <div class="flex items-center gap-3 rounded-2xl bg-soft px-3 py-3">
            <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-mint font-semibold uppercase text-primary">
              {String.first(@current_user.name || @current_user.email)}
            </span>
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold text-dark">
                {@current_user.name || "Learner"}
              </p>
              <p class="truncate text-xs text-muted">{@current_user.email}</p>
            </div>
          </div>
          <.link
            href={~p"/users/log_out"}
            method="delete"
            class="mt-3 flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-body transition hover:bg-soft hover:text-primary"
          >
            <.icon name="hero-arrow-left-on-rectangle" class="h-5 w-5" /> Log out
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
      class="group flex flex-col overflow-hidden rounded-3xl border border-black/5 bg-white shadow-sm transition duration-300 hover:-translate-y-1 hover:shadow-xl"
    >
      <div class="relative aspect-[16/9] overflow-hidden bg-mint">
        <img
          src={@card.course.thumbnail_key}
          alt=""
          class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-dark/55 via-dark/10 to-transparent"></div>
        <span class="absolute left-4 top-4 rounded-full bg-white/95 px-3 py-1 text-xs font-semibold text-primary shadow-sm">
          {progress_label(@card)}
        </span>
        <span
          id={@progress_id}
          class="absolute right-4 top-4 rounded-full bg-dark/45 px-2.5 py-1 text-xs font-semibold text-white backdrop-blur-sm"
        >
          {@card.progress.percent}%
        </span>
      </div>

      <div class="flex flex-1 flex-col p-6">
        <h3 class="text-lg font-semibold leading-snug text-dark">{@card.course.title}</h3>
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
            class="group/btn mt-5 flex items-center justify-between gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
          >
            {course_action(@card)}
            <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover/btn:bg-dark">
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

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@item.path}
      class={[
        "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition",
        if(@item.key == @active,
          do: "bg-mint text-primary",
          else: "text-body hover:bg-soft hover:text-primary"
        )
      ]}
    >
      <.icon name={@item.icon} class="h-5 w-5" />
      {@item.label}
    </.link>
    """
  end
end
