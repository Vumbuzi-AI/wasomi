defmodule WasomiWeb.AdminComponents do
  @moduledoc """
  Shared chrome for the authenticated admin area.

  `admin_layout/1` renders the persistent sidebar used across the internal
  admin routes (overview, courses, students, payments). The smaller helpers
  (`stat_card/1`, `page_header/1`, `status_badge/1`) keep the individual admin
  LiveViews consistent with the Wasomi design system. `bar_chart/1` and
  `column_chart/1` render dependency-free inline SVG charts for the
  analytics dashboard.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import WasomiWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: WasomiWeb.Endpoint,
    router: WasomiWeb.Router,
    statics: WasomiWeb.static_paths()

  @nav_items [
    %{key: :overview, label: "Overview", icon: "hero-chart-pie", path: "/admin"},
    %{key: :courses, label: "Courses", icon: "hero-academic-cap", path: "/admin/courses"},
    %{key: :students, label: "Students", icon: "hero-users", path: "/admin/students"},
    %{key: :payments, label: "Payments", icon: "hero-banknotes", path: "/admin/payments"}
  ]

  @doc """
  Wraps an admin page in the sidebar shell.

  ## Attributes

    * `:active` - key of the active nav item (`:overview`, `:courses`,
      `:students`, `:payments`). Defaults to `nil`.
    * `:current_user` - the signed-in admin, used for the profile footer.
  """
  attr :active, :atom, default: nil
  attr :current_user, :map, required: true
  slot :inner_block, required: true

  def admin_layout(assigns) do
    assigns = assign(assigns, :nav_items, @nav_items)

    ~H"""
    <div class="min-h-screen bg-soft text-dark lg:flex">
      <%!-- Mobile top bar --%>
      <div class="flex items-center justify-between border-b border-black/5 bg-white px-5 py-4 lg:hidden">
        <.link navigate={~p"/admin"} class="flex items-center gap-3 font-bold text-dark">
          <span class="grid h-9 w-9 place-items-center rounded-[10px] bg-dark text-white">K</span>
          <span>Wasomi <span class="text-primary">Admin</span></span>
        </.link>
        <button
          type="button"
          phx-click={JS.toggle(to: "#admin-sidebar")}
          class="grid h-10 w-10 place-items-center rounded-xl border border-black/10 text-dark"
        >
          <.icon name="hero-bars-3" class="h-5 w-5" />
        </button>
      </div>

      <%!-- Sidebar --%>
      <aside
        id="admin-sidebar"
        class="hidden w-full shrink-0 border-b border-black/5 bg-white lg:flex lg:h-screen lg:w-72 lg:flex-col lg:border-b-0 lg:border-r"
      >
        <div class="hidden px-6 py-7 lg:block">
          <.link navigate={~p"/admin"} class="flex items-center gap-3 font-bold text-dark">
            <span class="grid h-10 w-10 place-items-center rounded-[10px] bg-dark text-white">
              K
            </span>
            <span class="text-lg">Wasomi <span class="text-primary">Admin</span></span>
          </.link>
        </div>

        <nav class="flex-1 space-y-1 px-4 py-4 lg:py-2">
          <.nav_link :for={item <- @nav_items} item={item} active={@active} />
        </nav>

        <div class="border-t border-black/5 p-4">
          <.link
            navigate={~p"/dashboard"}
            class="mb-2 flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-body transition hover:bg-soft hover:text-primary"
          >
            <.icon name="hero-arrow-uturn-left" class="h-5 w-5" /> Back to learner area
          </.link>
          <div class="flex items-center gap-3 rounded-2xl bg-soft px-3 py-3">
            <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-mint font-semibold uppercase text-primary">
              {String.first(@current_user.name || @current_user.email)}
            </span>
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold text-dark">
                {@current_user.name || "Administrator"}
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
  Page heading band used at the top of each admin page.
  """
  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <p :if={@eyebrow} class="text-sm font-semibold uppercase tracking-wider text-primary">
          {@eyebrow}
        </p>
        <h1 class="mt-1 text-3xl font-semibold text-dark sm:text-4xl">{@title}</h1>
        <p :if={@subtitle != []} class="mt-2 max-w-2xl text-body">{render_slot(@subtitle)}</p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-3">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc """
  Compact metric tile for dashboard summaries.
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :hint, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <div class="rounded-3xl border border-black/5 bg-white p-6">
      <div class="flex items-center justify-between">
        <p class="text-sm font-medium text-muted">{@label}</p>
        <span class="grid h-10 w-10 place-items-center rounded-2xl bg-mint text-primary">
          <.icon name={@icon} class="h-5 w-5" />
        </span>
      </div>
      <p class="mt-4 text-3xl font-semibold text-dark">{@value}</p>
      <p :if={@hint} class="mt-1 text-xs text-muted">{@hint}</p>
    </div>
    """
  end

  @doc """
  Small coloured pill for a status enum (course / payment / enrollment).
  """
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize",
      status_classes(@status)
    ]}>
      {@status}
    </span>
    """
  end

  @doc """
  Horizontal bar chart on a fixed `:max` scale (0-100 by default) — used
  for percentages like completion rate, quiz score, or drop-off.

  `:data` is a list of `%{label:, value:, value_label:}` maps. `:value`
  drives the bar length; `:value_label` is the pre-formatted string shown
  next to it, so this component stays free of formatting logic. An
  optional `:tooltip` string shows on hover instead of `:value_label` —
  use it when the inline label is abbreviated and hovering should reveal
  the precise figure.
  """
  attr :title, :string, required: true
  attr :data, :list, required: true
  attr :max, :integer, default: 100
  attr :empty_message, :string, default: "No data yet."

  def bar_chart(assigns) do
    row_height = 36
    track_width = 300
    top_padding = 22

    bars =
      assigns.data
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        ratio = if assigns.max > 0, do: item.value / assigns.max, else: 0
        bar_width = min(max(ratio, 0), 1) * track_width
        tooltip = Map.get(item, :tooltip, item.value_label)
        tooltip_width = estimate_tooltip_width(tooltip)

        %{
          label: item.label,
          value_label: item.value_label,
          tooltip: tooltip,
          y: top_padding + index * row_height,
          bar_width: bar_width,
          tooltip_x: clamp(bar_width / 2 - tooltip_width / 2, 0, track_width - tooltip_width),
          tooltip_width: tooltip_width
        }
      end)

    assigns =
      assigns
      |> assign(:bars, bars)
      |> assign(:track_width, track_width)
      |> assign(:svg_height, top_padding + length(bars) * row_height)

    ~H"""
    <div>
      <p class="text-sm font-medium text-muted">{@title}</p>
      <svg
        :if={@data != []}
        viewBox={"0 0 #{@track_width} #{@svg_height}"}
        class="mt-3 w-full"
        role="img"
        aria-label={@title}
      >
        <g :for={bar <- @bars} transform={"translate(0, #{bar.y})"} class="group">
          <rect x="0" y="0" width={@track_width} height="30" fill="transparent" />
          <text x="0" y="12" class="fill-body text-[11px]">{bar.label}</text>
          <text x={@track_width} y="12" text-anchor="end" class="fill-dark text-[11px] font-semibold">
            {bar.value_label}
          </text>
          <rect x="0" y="18" width={@track_width} height="8" rx="4" class="fill-black/5" />
          <rect x="0" y="18" width={bar.bar_width} height="8" rx="4" class="fill-primary" />

          <g class="pointer-events-none opacity-0 transition-opacity duration-150 group-hover:opacity-100">
            <rect
              x={bar.tooltip_x}
              y="-20"
              width={bar.tooltip_width}
              height="16"
              rx="4"
              class="fill-dark"
            />
            <text
              x={bar.tooltip_x + bar.tooltip_width / 2}
              y="-8"
              text-anchor="middle"
              class="fill-white text-[10px] font-semibold"
            >
              {bar.tooltip}
            </text>
          </g>
        </g>
      </svg>
      <p :if={@data == []} class="mt-3 rounded-2xl bg-soft p-6 text-center text-sm text-muted">
        {@empty_message}
      </p>
    </div>
    """
  end

  @doc """
  Vertical column chart scaled to the data's own maximum — used for
  monthly revenue, where there's no fixed upper bound like a percentage.

  Same `%{label:, value:, value_label:}` shape as `bar_chart/1`, plus the
  same optional `:tooltip` override shown on hover.
  """
  attr :title, :string, required: true
  attr :data, :list, required: true
  attr :empty_message, :string, default: "No data yet."

  def column_chart(assigns) do
    # Fixed canvas, same principle as bar_chart/1's constant track_width —
    # the number of columns changes how that space is divided, never the
    # canvas itself, so the aspect ratio stays sane whether there's 1
    # column or 12 and nothing needs non-uniform (distorting) scaling.
    chart_width = 600
    bars_area_height = 160
    top_padding = 36

    max_value =
      case assigns.data do
        [] -> 0
        data -> data |> Enum.map(& &1.value) |> Enum.max()
      end

    count = length(assigns.data)
    column_width = if count > 0, do: chart_width / count, else: 0
    bar_width = column_width |> Kernel.*(0.5) |> min(60)

    bars =
      assigns.data
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        height = if max_value > 0, do: item.value / max_value * bars_area_height, else: 0
        height = max(height, 1)
        center_x = index * column_width + column_width / 2
        tooltip = Map.get(item, :tooltip, item.value_label)
        tooltip_width = estimate_tooltip_width(tooltip)

        %{
          label: item.label,
          value_label: item.value_label,
          tooltip: tooltip,
          x: center_x - bar_width / 2,
          y: top_padding + bars_area_height - height,
          width: bar_width,
          height: height,
          center_x: center_x,
          tooltip_x: clamp(center_x - tooltip_width / 2, 0, chart_width - tooltip_width),
          tooltip_width: tooltip_width
        }
      end)

    assigns =
      assigns
      |> assign(:bars, bars)
      |> assign(:chart_width, chart_width)
      |> assign(:column_width, column_width)
      |> assign(:bars_area_height, bars_area_height)
      |> assign(:top_padding, top_padding)

    ~H"""
    <div>
      <p class="text-sm font-medium text-muted">{@title}</p>
      <svg
        :if={@data != []}
        viewBox={"0 0 #{@chart_width} #{@top_padding + @bars_area_height + 34}"}
        class="mt-3 w-full"
        role="img"
        aria-label={@title}
      >
        <g :for={bar <- @bars} class="group">
          <rect
            x={bar.center_x - @column_width / 2}
            y="0"
            width={@column_width}
            height={@top_padding + @bars_area_height + 18}
            fill="transparent"
          />
          <rect x={bar.x} y={bar.y} width={bar.width} height={bar.height} rx="4" class="fill-primary" />
          <text
            x={bar.center_x}
            y={bar.y - 6}
            text-anchor="middle"
            class="fill-dark text-[10px] font-semibold"
          >
            {bar.value_label}
          </text>
          <text
            x={bar.center_x}
            y={@top_padding + @bars_area_height + 18}
            text-anchor="middle"
            class="fill-muted text-[10px]"
          >
            {bar.label}
          </text>

          <g class="pointer-events-none opacity-0 transition-opacity duration-150 group-hover:opacity-100">
            <rect
              x={bar.tooltip_x}
              y={bar.y - 30}
              width={bar.tooltip_width}
              height="16"
              rx="4"
              class="fill-dark"
            />
            <text
              x={bar.tooltip_x + bar.tooltip_width / 2}
              y={bar.y - 18}
              text-anchor="middle"
              class="fill-white text-[10px] font-semibold"
            >
              {bar.tooltip}
            </text>
          </g>
        </g>
      </svg>
      <p :if={@data == []} class="mt-3 rounded-2xl bg-soft p-6 text-center text-sm text-muted">
        {@empty_message}
      </p>
    </div>
    """
  end

  defp estimate_tooltip_width(text), do: max(String.length(text) * 6.5 + 16, 40)

  defp clamp(value, min, max), do: value |> Kernel.max(min) |> Kernel.min(max)

  defp status_classes(status) when status in [:published, :successful, :active],
    do: "bg-mint text-primary"

  defp status_classes(status) when status in [:draft, :pending],
    do: "bg-amber-50 text-amber-700"

  defp status_classes(:in_review), do: "bg-blue-50 text-blue-700"
  defp status_classes(:failed), do: "bg-red-50 text-red-600"
  defp status_classes(_status), do: "bg-soft text-body"

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
