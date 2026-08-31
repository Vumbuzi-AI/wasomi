defmodule WasomiWeb.AdminComponents do
  @moduledoc """
  Shared chrome for the authenticated admin area.

  `admin_layout/1` renders the persistent sidebar used across the internal
  admin routes (overview, courses, students, payments). The smaller helpers
  (`stat_card/1`, `page_header/1`, `status_badge/1`) keep the individual admin
  LiveViews consistent with the Wasomi design system. `column_chart/1`
  renders a dependency-free inline SVG chart for the analytics dashboard.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import WasomiWeb.CoreComponents, only: [icon: 1, input: 1, error: 1, translate_error: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: WasomiWeb.Endpoint,
    router: WasomiWeb.Router,
    statics: WasomiWeb.static_paths()

  @nav_items [
    %{key: :overview, label: "Overview", icon: "hero-chart-pie", path: "/admin"},
    %{key: :courses, label: "Courses", icon: "hero-academic-cap", path: "/admin/courses"},
    %{
      key: :discussions,
      label: "Discussions",
      icon: "hero-chat-bubble-left-right",
      path: "/admin/discussions"
    },
    %{key: :mentors, label: "Mentors", icon: "hero-user-group", path: "/admin/mentors"},
    %{key: :students, label: "Students", icon: "hero-users", path: "/admin/students"},
    %{
      key: :invitations,
      label: "Admin invitations",
      icon: "hero-user-plus",
      path: "/admin/invitations"
    },
    %{key: :payments, label: "Payments", icon: "hero-banknotes", path: "/admin/payments"},
    %{key: :analytics, label: "Analytics", icon: "hero-chart-bar", path: "/admin/analytics"},
    %{
      key: :landing_images,
      label: "Landing page",
      icon: "hero-photo",
      path: "/admin/landing-images"
    }
  ]

  @doc """
  Wraps an admin page in the sidebar shell.

  ## Attributes

    * `:active` - key of the active nav item (`:overview`, `:courses`,
      `:students`, `:payments`, `:analytics`, `:landing_images`). Defaults
      to `nil`.
    * `:current_user` - the signed-in admin, used for the profile footer.
  """
  attr :active, :atom, default: nil
  attr :current_user, :map, required: true
  slot :inner_block, required: true

  def admin_layout(assigns) do
    assigns = assign(assigns, :nav_items, @nav_items)

    ~H"""
    <div class="min-h-screen bg-surface text-ink lg:flex">
      <%!-- Mobile top bar --%>
      <div class="flex items-center justify-between border-b border-black/5 bg-white px-5 py-4 lg:hidden">
        <.link navigate={~p"/admin"} class="flex flex-col items-start">
          <img src={~p"/images/logo.png"} alt="Wasomi" class="h-4 w-auto" />
          <span class="text-[10px] font-bold tracking-widest text-primary">ADMIN</span>
        </.link>
        <button
          type="button"
          phx-click={JS.toggle(to: "#admin-sidebar")}
          class="grid h-10 w-10 place-items-center rounded-xl border border-black/10 text-ink"
        >
          <.icon name="hero-bars-3" class="h-5 w-5" />
        </button>
      </div>

      <%!-- Sidebar --%>
      <aside
        id="admin-sidebar"
        phx-update="ignore"
        class="app-sidebar hidden w-full shrink-0 border-b border-black/5 bg-white lg:flex lg:h-screen lg:w-72 lg:flex-col lg:border-b-0 lg:border-r"
      >
        <div class="sidebar-header hidden items-center justify-between px-6 py-7 lg:flex">
          <.link navigate={~p"/admin"} class="sidebar-label flex flex-col items-start">
            <img src={~p"/images/logo.png"} alt="Wasomi" class="h-5 w-auto" />
            <span class="text-xs font-bold tracking-widest text-primary">ADMIN</span>
          </.link>
          <button
            type="button"
            id="sidebar-toggle"
            phx-hook="SidebarToggle"
            class="grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-black/10 text-ink transition hover:border-primary hover:text-primary"
            title="Collapse sidebar"
          >
            <.icon name="hero-chevron-double-left" class="sidebar-toggle-icon h-4 w-4" />
          </button>
        </div>

        <nav class="flex-1 space-y-1 px-4 py-4 lg:py-2">
          <.nav_link :for={item <- @nav_items} item={item} active={@active} />
        </nav>

        <div class="border-t border-black/5 p-4">
          <.link
            navigate={~p"/dashboard"}
            class="sidebar-row group relative mb-2 flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-body transition hover:bg-surface hover:text-primary"
          >
            <.icon name="hero-arrow-uturn-left" class="h-5 w-5 shrink-0" />
            <span class="sidebar-label inline-block">Back to learner area</span>
            <.sidebar_tooltip label="Back to learner area" />
          </.link>
          <div class="sidebar-row group relative flex items-center gap-3 rounded-2xl bg-surface px-3 py-3">
            <span class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-mint font-semibold uppercase text-primary">
              {String.first(@current_user.name || @current_user.email)}
            </span>
            <div class="sidebar-label min-w-0">
              <p class="truncate text-sm font-semibold text-ink">
                {@current_user.name || "Administrator"}
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
  Page heading band used at the top of each admin page.
  """
  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-start justify-between gap-4 rounded-3xl border border-black/5 bg-white p-6 shadow-card">
      <div>
        <p :if={@eyebrow} class="text-sm font-semibold uppercase tracking-wider text-primary">
          {@eyebrow}
        </p>
        <h1 class="mt-1 text-3xl font-semibold text-ink sm:text-4xl">{@title}</h1>
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
    <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
      <div class="flex items-center justify-between">
        <p class="text-sm font-medium text-body">{@label}</p>
        <span class="grid h-10 w-10 place-items-center rounded-xl border border-primary/40 bg-mint text-primary">
          <.icon name={@icon} class="h-5 w-5" />
        </span>
      </div>
      <p class="mt-4 text-3xl font-bold text-ink">{@value}</p>
      <p :if={@hint} class="mt-1 text-xs text-muted">{@hint}</p>
    </div>
    """
  end

  @doc """
  Labeled horizontal percentage bar — two stacked instances (completion /
  quiz score) make up each row of the analytics "by module" chart.
  """
  attr :label, :string, required: true
  attr :percent, :integer, required: true
  attr :color, :string, required: true

  def percent_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="w-24 shrink-0 text-sm font-semibold text-ink">{@label}</span>
      <div class="h-3 flex-1 overflow-hidden rounded-full border border-black/10 bg-white">
        <div class={["h-full rounded-full", @color]} style={"width: #{@percent}%"} />
      </div>
      <span class="w-10 shrink-0 text-right text-sm font-semibold text-ink">{@percent}%</span>
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
  Body copy for the "archive this course?" confirm dialog, shared by the
  admin courses list and the course edit modal so the two surfaces can't
  drift apart in wording. `incomplete_enrollee_count` comes from
  `Wasomi.Learning.count_incomplete_enrollees/1` — purely informational,
  archiving itself is never blocked by it.
  """
  def archive_confirmation_copy(0) do
    "This removes it from the public catalog immediately. No enrolled learners are affected."
  end

  def archive_confirmation_copy(incomplete_enrollee_count) do
    "This removes it from the public catalog immediately. " <>
      pluralize(incomplete_enrollee_count, "learner") <>
      " " <>
      if(incomplete_enrollee_count == 1, do: "hasn't", else: "haven't") <>
      " finished yet — they'll keep their access."
  end

  @doc ~s|Formats a count with its unit, pluralizing past 1 (`"1 learner"`, `"2 learners"`).|
  def pluralize(1, unit), do: "1 #{unit}"
  def pluralize(count, unit), do: "#{count} #{unit}s"

  @doc """
  The full pre-publish checklist — every stage shown, not just failures, so
  an admin sees what's ready alongside what's blocking. Expects
  `PublishGuard.checklist/1`'s shape: `%{stage:, status:, reasons:}`, where
  `status` is `:passed`, `:failed`, or `:not_applicable` (nothing to check
  yet, e.g. no lectures — shown as neutral, not a misleading checkmark).

  Rows stagger in (`animate-checklist-in`, `tailwind.config.js`) purely for
  visual polish — the check itself is instant, kept short so it's never a
  real delay for an admin re-checking after each fix.
  """
  attr :stages, :list, required: true

  def publish_checklist(assigns) do
    ~H"""
    <div class="mt-6 divide-y divide-black/5 border-y border-black/5">
      <div
        :for={{stage, index} <- Enum.with_index(@stages)}
        style={"animation-delay: #{min(index, 6) * 60}ms"}
        class="flex items-start gap-3 py-4 opacity-0 animate-checklist-in"
      >
        <span class={[
          "mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full",
          checklist_icon_classes(stage.status)
        ]}>
          <.icon name={checklist_icon(stage.status)} class="h-3.5 w-3.5" />
        </span>
        <div class="min-w-0 flex-1">
          <p class={[
            "text-sm font-semibold leading-5",
            stage.status in [:passed, :failed] && "text-ink",
            stage.status == :not_applicable && "text-muted"
          ]}>
            {stage.stage}
            <span :if={stage.status == :not_applicable} class="font-normal">
              — nothing to check yet
            </span>
          </p>
          <ul
            :if={stage.status == :failed and stage.reasons != []}
            class="mt-1.5 space-y-1 text-xs font-medium text-primary"
          >
            <li :for={reason <- stage.reasons} class="flex gap-2">
              <span class="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-primary"></span>
              <span>{reason}</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp checklist_icon_classes(:passed), do: "text-emerald-600"
  defp checklist_icon_classes(:failed), do: "text-primary"
  defp checklist_icon_classes(:not_applicable), do: "text-muted"

  defp checklist_icon(:passed), do: "hero-check-mini"
  defp checklist_icon(:failed), do: "hero-exclamation-circle-mini"
  defp checklist_icon(:not_applicable), do: "hero-minus-mini"

  @doc """
  Vertical column chart scaled to the data's own maximum — used for
  monthly revenue, where there's no fixed upper bound like a percentage.

  `:data` is a list of `%{label:, value:, value_label:}` maps. `:value`
  drives the bar height; `:value_label` is the pre-formatted string shown
  next to it, so this component stays free of formatting logic. An
  optional `:tooltip` string shows on hover instead of `:value_label` —
  use it when the inline label is abbreviated and hovering should reveal
  the precise figure.
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
            class="fill-ink text-[10px] font-semibold"
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
              class="fill-ink"
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
      <p :if={@data == []} class="mt-3 rounded-2xl bg-surface p-6 text-center text-sm text-muted">
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

  defp status_classes(:failed), do: "bg-red-50 text-red-600"
  defp status_classes(_status), do: "bg-surface text-body"

  attr :item, :map, required: true
  attr :active, :atom, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@item.path}
      class={[
        "sidebar-row group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition",
        if(@item.key == @active,
          do: "bg-dark text-white shadow-sm",
          else: "text-body hover:bg-surface hover:text-primary"
        )
      ]}
    >
      <.icon name={@item.icon} class="h-5 w-5 shrink-0" />
      <span class="sidebar-label inline-block">{@item.label}</span>
      <.sidebar_tooltip label={@item.label} />
    </.link>
    """
  end

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

  @doc """
  Renders errors for a single form field.
  """
  attr :field, Phoenix.HTML.FormField, required: true

  def field_error(assigns) do
    ~H"""
    <.error :for={error <- @field.errors}>{translate_error(error)}</.error>
    """
  end

  @doc """
  Renders an interactive question editor form (shared between module quizzes and lecture quizzes).
  """
  attr :form, :any, required: true
  attr :question, :any, required: true
  attr :dirty, :boolean, default: true

  def question_form(assigns) do
    assigns =
      assign(
        assigns,
        :input_prefix,
        if(assigns.question, do: "question-#{assigns.question.id}", else: "new-question")
      )

    ~H"""
    <.form
      for={@form}
      id={if @question, do: "question-form-#{@question.id}", else: "new-question-form"}
      phx-change={if @question, do: "validate_question", else: "validate_new_question"}
      phx-submit={if @question, do: "save_question", else: "save_new_question"}
      phx-value-id={@question && @question.id}
      class="space-y-5"
    >
      <.input
        field={@form[:prompt]}
        id={"#{@input_prefix}-prompt"}
        type="textarea"
        label="Question text"
      />
      <.input
        field={@form[:explanation]}
        id={"#{@input_prefix}-explanation"}
        type="textarea"
        label="Explanation"
        placeholder="Explain why the selected answer is correct"
      />

      <fieldset>
        <legend class="mb-3 text-sm font-semibold text-ink">
          Answer options <span class="font-normal text-body">(select the correct answer)</span>
        </legend>
        <div class="space-y-3">
          <.inputs_for :let={option_form} field={@form[:question_options]}>
            <div class="flex items-start gap-3">
              <input
                type="radio"
                name={"#{@input_prefix}[correct_option_id]"}
                value={option_form.index}
                checked={option_form[:correct].value == true}
                aria-label={"Mark option #{option_form.index + 1} correct"}
                class="mt-3 h-4 w-4 border-black/20 text-primary focus:ring-primary"
              />
              <input
                type="hidden"
                name={"#{option_form.name}[position]"}
                value={option_form.index + 1}
              />
              <div class="flex-1">
                <.input
                  field={option_form[:label]}
                  id={"#{@input_prefix}-option-#{option_form.index}"}
                  type="text"
                  label={"Option #{option_form.index + 1}"}
                />
              </div>
              <button
                :if={length(@form.impl.to_form(@form.source, @form, :question_options, [])) > 2}
                type="button"
                phx-click="remove_option"
                phx-value-id={if @question, do: @question.id, else: "new"}
                phx-value-index={option_form.index}
                tabindex="-1"
                class="mt-8 p-2 text-muted hover:text-red-500 rounded-lg hover:bg-surface transition shrink-0"
                title="Remove option"
              >
                <.icon name="hero-trash" class="h-4 w-4" />
              </button>
            </div>
          </.inputs_for>
          <div
            :if={length(@form.impl.to_form(@form.source, @form, :question_options, [])) < 4}
            class="pt-1"
          >
            <button
              type="button"
              phx-click="add_option"
              phx-value-id={if @question, do: @question.id, else: "new"}
              class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-3 py-1.5 text-xs font-semibold text-ink transition hover:bg-surface hover:text-primary active:scale-[0.96]"
            >
              <.icon name="hero-plus-circle" class="h-4 w-4" /> Add option
            </button>
          </div>
          <.error :for={err <- @form[:question_options].errors}>{translate_error(err)}</.error>
        </div>
      </fieldset>

      <div class="flex items-center gap-4">
        <button
          type="submit"
          disabled={@question && !@dirty}
          class="rounded-full bg-ink px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-primary active:scale-[0.96] disabled:cursor-not-allowed disabled:opacity-40"
        >
          {if @question, do: "Save question", else: "Add question"}
        </button>
        <button
          :if={is_nil(@question)}
          type="button"
          phx-click="cancel_new_question"
          class="text-sm font-medium text-muted hover:text-ink transition active:scale-[0.96]"
        >
          Cancel
        </button>
      </div>
    </.form>
    """
  end
end
