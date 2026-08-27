defmodule WasomiWeb.AdminLive.Analytics do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Catalog, Enrollments, Paginate, Payments}
  alias Wasomi.Catalog.Analytics

  @page_size 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Analytics")
     |> assign(:courses, Catalog.list_courses())
     |> assign(:students, Accounts.list_users(role: :learner))
     |> assign(:active_tab, :overview)
     |> assign(:module_query, "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    opts =
      [
        course_id: parse_id(params["course_id"]),
        user_id: parse_id(params["user_id"]),
        from: parse_date(params["from"]),
        to: parse_date(params["to"])
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    filter_form =
      to_form(
        %{
          "course_id" => params["course_id"] || "",
          "user_id" => params["user_id"] || "",
          "from" => params["from"] || "",
          "to" => params["to"] || ""
        },
        as: :filter
      )

    {:noreply,
     socket
     |> assign(:filter_form, filter_form)
     |> assign(:has_filters?, opts != [])
     |> assign(:export_query, raw_query_params(params))
     |> assign(:page_number, Paginate.parse_page(params["page"]))
     |> assign_analytics(opts)}
  end

  @impl true
  def handle_event("filter", %{"filter" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/analytics?#{raw_query_params(params)}")}
  end

  def handle_event("search_modules", %{"q" => query}, socket) do
    {:noreply, assign(socket, :module_query, query)}
  end

  def handle_event("switch_tab", %{"tab" => "overview"}, socket) do
    {:noreply, assign(socket, :active_tab, :overview)}
  end

  def handle_event("switch_tab", %{"tab" => "revenue"}, socket) do
    {:noreply, assign(socket, :active_tab, :revenue)}
  end

  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:analytics} current_user={@current_user}>
      <div class="analytics-page w-full space-y-6 px-5 py-8 lg:px-8 lg:py-10">
        <div class="analytics-card flex flex-wrap items-center justify-between gap-8 px-6 py-7 lg:px-10">
          <div>
            <h1 class="text-4xl font-medium leading-none text-ink lg:text-[44px]">Analytics</h1>
            <p class="mt-4 text-lg text-body">
              Track learning performance, revenue and where learners leave a course.
            </p>
          </div>
          <form phx-change="search_modules" class="relative w-full lg:w-[38%] lg:min-w-[420px]">
            <.icon
              name="hero-magnifying-glass"
              class="pointer-events-none absolute left-5 top-1/2 h-6 w-6 -translate-y-1/2 text-primary"
            />
            <input
              type="search"
              name="q"
              value={@module_query}
              placeholder="Search modules or courses"
              phx-debounce="200"
              class="h-14 w-full rounded-2xl border border-neutral-700 bg-white pl-14 pr-5 text-lg text-ink placeholder:text-muted focus:border-primary focus:ring-primary"
            />
          </form>
        </div>

        <div class="analytics-summary grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Module completion"
            value={percent_or_dash(@module_completion_avg)}
            icon="hero-rectangle-stack"
            hint="Average across learners"
          />
          <.stat_card
            label="Average quiz score"
            value={percent_or_dash(@module_quiz_avg)}
            icon="hero-clipboard-document-check"
            hint="Across published module quizzes"
          />
          <.stat_card
            label="Attributed revenue"
            value={Payments.format_minor(@attributed_revenue_minor)}
            icon="hero-banknotes"
            hint={"#{@range_label}"}
          />
          <.stat_card
            label="Active learners"
            value={@active_learners}
            icon="hero-users"
            hint="Included in this report"
          />
        </div>

        <section class="analytics-card px-6 py-7 lg:px-8">
          <div class="flex items-center gap-3">
            <.icon name="hero-chart-bar" class="h-5 w-5 text-primary" />
            <div>
              <h2 class="text-lg font-semibold text-ink">Report filters</h2>
              <p class="text-sm text-muted">All charts update together</p>
            </div>
          </div>

          <.form
            id="filter-form"
            for={@filter_form}
            phx-change="filter"
            class="mt-6 grid gap-5 lg:grid-cols-3"
          >
            <div>
              <.input
                field={@filter_form[:course_id]}
                type="select"
                label="Course"
                prompt="All courses"
                options={Enum.map(@courses, &{&1.title, &1.id})}
              />
            </div>
            <div>
              <label class="block text-sm font-semibold text-body">Date range</label>
              <div class="mt-2 grid min-h-12 grid-cols-2 overflow-hidden rounded-xl border border-neutral-700 bg-white">
                <input
                  name={@filter_form[:from].name}
                  value={@filter_form[:from].value}
                  type="date"
                  max="today"
                  aria-label="Date range from"
                  class="min-w-0 border-0 bg-transparent px-3 text-sm font-semibold text-body focus:ring-0"
                />
                <input
                  name={@filter_form[:to].name}
                  value={@filter_form[:to].value}
                  type="date"
                  max="today"
                  aria-label="Date range to"
                  class="min-w-0 border-0 border-l border-neutral-200 bg-transparent px-3 text-sm font-semibold text-body focus:ring-0"
                />
              </div>
            </div>
            <div>
              <.input
                field={@filter_form[:user_id]}
                type="select"
                label="Student"
                prompt="All students"
                options={Enum.map(@students, &{student_option_label(&1), &1.id})}
              />
            </div>
          </.form>

          <div class="sr-only">
            <div class="flex items-center gap-2 rounded-full border border-black/5 bg-surface p-1.5">
              <button
                type="button"
                phx-click={JS.push("switch_tab", value: %{tab: "overview"})}
                class={[
                  "rounded-full px-5 py-2.5 text-sm font-medium transition",
                  if(@active_tab == :overview,
                    do: "bg-ink text-white",
                    else: "text-body hover:text-ink"
                  )
                ]}
              >
                Overview
              </button>
              <button
                type="button"
                phx-click={JS.push("switch_tab", value: %{tab: "revenue"})}
                class={[
                  "rounded-full px-5 py-2.5 text-sm font-medium transition",
                  if(@active_tab == :revenue,
                    do: "bg-ink text-white",
                    else: "text-body hover:text-ink"
                  )
                ]}
              >
                Revenue
              </button>
            </div>

            <.link
              :if={@has_filters?}
              patch={~p"/admin/analytics"}
              class="text-sm font-medium text-primary hover:text-ink"
            >
              Clear filters
            </.link>
            <.link
              href={~p"/admin/exports/quiz_results?#{@export_query}"}
              class="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:text-ink"
            >
              <.icon name="hero-document-arrow-down" class="h-4 w-4" /> Export quiz results CSV
            </.link>
          </div>
        </section>

        <div :if={@active_tab == :overview} class="space-y-6">
          <section class="analytics-card overflow-hidden">
            <div class="flex flex-wrap items-baseline justify-between gap-3 border-b border-neutral-700 px-6 py-7 lg:px-8">
              <div>
                <p class="text-xs font-bold uppercase tracking-wider text-primary">Journey</p>
                <h3 class="mt-2 text-3xl font-medium text-ink">Conversion funnel</h3>
              </div>
              <p :if={@funnel_overall_conversion} class="text-sm text-body">
                <span class="font-semibold text-primary">{@funnel_overall_conversion}%</span>
                overall, checkout to certificate
              </p>
            </div>
            <div class="flex flex-wrap items-stretch gap-3 px-6 py-7 lg:px-8">
              <div :for={step <- @funnel} class="contents">
                <div class="min-w-[140px] flex-1 rounded-2xl border border-black/5 bg-white p-4 text-center shadow-sm">
                  <p class="text-xs font-semibold uppercase tracking-wide text-body">{step.step}</p>
                  <p class="mt-2 text-3xl font-bold text-ink">{step.count}</p>
                  <p class="mt-1 text-xs font-medium text-body">
                    {if step.percent_of_previous,
                      do: "#{step.percent_of_previous}% of previous",
                      else: raw("&nbsp;")}
                  </p>
                </div>
                <.icon
                  :if={!step.last?}
                  name="hero-chevron-right"
                  class="h-5 w-5 shrink-0 self-center text-body"
                />
              </div>
            </div>
          </section>

          <section class="analytics-card overflow-hidden">
            <div class="flex flex-wrap items-start justify-between gap-4 border-b border-neutral-700 px-6 py-7 lg:px-8">
              <div>
                <p class="text-xs font-bold uppercase tracking-wider text-primary">
                  Learning performance
                </p>
                <h3 class="mt-2 text-3xl font-medium text-ink">
                  Completion and quiz score by module
                </h3>
                <p class="mt-2 text-base text-body">
                  Two measures share one percentage scale for direct comparison.
                </p>
              </div>
              <span class="rounded-xl border border-neutral-700 px-5 py-3 text-base font-semibold text-ink">
                All students
              </span>
            </div>

            <div :if={@filtered_module_rows != []} class="px-6 pb-6 pt-5 lg:px-8">
              <div class="mb-5 flex justify-end gap-7 text-sm font-semibold text-body">
                <span class="flex items-center gap-2">
                  <span class="h-4 w-4 rounded bg-ink" /> Completion rate
                </span>
                <span class="flex items-center gap-2">
                  <span class="h-4 w-4 rounded bg-primary" /> Average quiz score
                </span>
              </div>
              <div class="ml-[250px] flex items-center justify-between border-b border-neutral-700 pb-3 text-sm text-body">
                <span>0%</span>
                <span>25%</span>
                <span>50%</span>
                <span>75%</span>
                <span>100%</span>
              </div>

              <div class="divide-y divide-black/5">
                <div
                  :for={row <- @filtered_module_rows}
                  class="grid items-center gap-5 py-6 sm:grid-cols-[220px_1fr]"
                >
                  <p class="text-lg font-medium text-ink">{row.title}</p>
                  <div class="space-y-3">
                    <.percent_bar label="Completion" percent={row.completion_percent} color="bg-ink" />
                    <.percent_bar
                      label="Quiz score"
                      percent={row.quiz_score_percent || 0}
                      color="bg-primary"
                    />
                  </div>
                </div>
              </div>
            </div>

            <p
              :if={@filtered_module_rows == [] and @module_rows != []}
              class="mx-6 my-6 rounded-xl border border-black/5 bg-surface/70 p-8 text-center text-sm text-body lg:mx-8"
            >
              No modules match "{@module_query}".
            </p>

            <p
              :if={@module_rows == []}
              class="mx-6 my-6 rounded-xl border border-black/5 bg-surface/70 p-8 text-center text-sm text-body lg:mx-8"
            >
              Select a course above to see module-level completion and quiz performance.
            </p>
          </section>

          <div class="grid gap-6 lg:grid-cols-2">
            <section class="analytics-card overflow-hidden">
              <div class="flex min-h-36 flex-wrap items-start justify-between gap-3 border-b border-neutral-700 px-6 py-7 lg:px-8">
                <div>
                  <p class="text-xs font-bold uppercase tracking-wider text-primary">Revenue</p>
                  <h3 class="mt-2 text-3xl font-medium text-ink">Course revenue</h3>
                  <p class="mt-3 text-base text-body">Income attributed to the active filters.</p>
                </div>
                <span class="rounded-xl border border-neutral-700 px-5 py-3 text-base font-semibold text-ink">
                  {Payments.format_minor(@attributed_revenue_minor)}
                </span>
              </div>

              <div :if={@revenue_by_course != []} class="min-h-[360px] space-y-5 px-6 py-10 lg:px-8">
                <div :for={row <- @revenue_by_course}>
                  <div class="flex items-center justify-between text-sm">
                    <span class="font-semibold text-ink">{row.title}</span>
                    <span class="font-semibold text-ink">
                      {Payments.format_minor(row.revenue_minor)}
                    </span>
                  </div>
                  <div class="mt-2 h-3 overflow-hidden rounded-full bg-neutral-100">
                    <div
                      class="h-full rounded-full bg-ink"
                      style={"width: #{revenue_bar_percent(row.revenue_minor, @revenue_by_course)}%"}
                    />
                  </div>
                </div>
              </div>

              <p
                :if={@revenue_by_course == []}
                class="mx-6 my-6 rounded-xl border border-black/5 bg-surface/70 p-8 text-center text-sm text-body lg:mx-8"
              >
                No successful payments in range.
              </p>
            </section>

            <section class="analytics-card overflow-hidden">
              <div class="flex min-h-36 flex-wrap items-start justify-between gap-3 border-b border-neutral-700 px-6 py-7 lg:px-8">
                <div>
                  <p class="text-xs font-bold uppercase tracking-wider text-primary">Drop-off</p>
                  <h3 class="mt-2 text-3xl font-medium text-ink">Learner retention</h3>
                  <p class="mt-3 text-base text-body">Learners remaining after each module.</p>
                </div>
                <span class="rounded-xl border border-neutral-700 px-5 py-3 text-base font-semibold text-ink">
                  {retained_label(@filtered_module_rows)}
                </span>
              </div>

              <div :if={@filtered_module_rows != []} class="divide-y divide-black/5 px-6 py-6 lg:px-8">
                <div
                  :for={{row, index} <- Enum.with_index(@filtered_module_rows, 1)}
                  class="flex items-start gap-4 py-5 first:pt-0 last:pb-0"
                >
                  <span class="mt-0.5 grid h-10 w-10 shrink-0 place-items-center rounded-full border border-primary text-sm font-bold text-primary">
                    {String.pad_leading(Integer.to_string(index), 2, "0")}
                  </span>
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center justify-between gap-3">
                      <p class="font-semibold text-ink">{row.title}</p>
                      <span class="text-sm font-bold text-primary">{row.completion_percent}%</span>
                    </div>
                    <div class="mt-2 h-3 overflow-hidden rounded-full bg-neutral-100">
                      <div
                        class="h-full rounded-full bg-primary"
                        style={"width: #{row.completion_percent}%"}
                      />
                    </div>
                    <p class="mt-1 text-xs text-muted">
                      {row.remaining_learners} learners remaining
                    </p>
                  </div>
                </div>
              </div>

              <p
                :if={@filtered_module_rows == [] and @module_rows == []}
                class="mx-6 my-6 rounded-xl border border-black/5 bg-surface/70 p-8 text-center text-sm text-body lg:mx-8"
              >
                Select a course above to see learner retention by module.
              </p>
            </section>
          </div>

          <section class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
            <h3 class="text-base font-semibold text-ink">Course leaderboard</h3>
            <p class="mt-1 text-xs text-body">Richest-first. Click a course for detail.</p>
            <.paginated_table
              page={@scorecards_page.page}
              total_pages={@scorecards_page.total_pages}
              path_fn={&leaderboard_path(@export_query, &1)}
            >
              <div class="mt-4 overflow-x-auto rounded-2xl border border-black/5">
                <table class="w-full text-left text-sm">
                  <thead class="border-b border-black/5 bg-surface text-xs font-semibold uppercase tracking-wide text-body">
                    <tr>
                      <th class="px-6 py-4">Course</th>
                      <th class="px-6 py-4">Enrolled</th>
                      <th class="px-6 py-4">Completion rate</th>
                      <th class="px-6 py-4">Quiz pass rate</th>
                      <th class="px-6 py-4">Revenue</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-black/5">
                    <tr
                      :for={row <- @scorecards_page.entries}
                      class="transition even:bg-surface/50 hover:bg-mint/45"
                    >
                      <td class="px-6 py-4">
                        <.link
                          navigate={~p"/admin/courses/#{row.slug}"}
                          class="font-medium text-ink hover:text-primary"
                        >
                          {row.title}
                        </.link>
                      </td>
                      <td class="px-6 py-4 text-body">{row.enrolled}</td>
                      <td class="px-6 py-4">
                        <.rate_bar percent={row.completion_rate_percent} />
                      </td>
                      <td class="px-6 py-4">
                        <.rate_bar percent={row.quiz_pass_rate_percent} />
                      </td>
                      <td class="px-6 py-4 font-semibold text-ink">
                        {Payments.format_minor(row.revenue_minor)}
                      </td>
                    </tr>
                  </tbody>
                </table>
                <p :if={@scorecards_page.entries == []} class="p-8 text-center text-body">
                  No courses yet.
                </p>
              </div>
            </.paginated_table>
          </section>
        </div>

        <div :if={@active_tab == :revenue}>
          <section class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
            <div class="rounded-2xl border border-black/5 bg-white p-5">
              <.column_chart
                title="Monthly revenue"
                data={@revenue_chart}
                empty_message="No successful payments in range."
              />
            </div>
          </section>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp assign_analytics(socket, opts) do
    course_id = Keyword.get(opts, :course_id)
    user_id = Keyword.get(opts, :user_id)
    funnel = Analytics.funnel(opts)
    scorecards = Analytics.course_scorecards(opts)
    revenue_by_course = Analytics.revenue_by_course(opts)
    module_rows = build_module_rows(course_id, opts)
    module_query = Map.get(socket.assigns, :module_query, "")

    socket
    |> assign(:funnel, funnel_widget_data(funnel))
    |> assign(:funnel_overall_conversion, funnel_overall_conversion(funnel))
    |> assign(
      :scorecards_page,
      Paginate.paginate_list(scorecards, socket.assigns.page_number, @page_size)
    )
    |> assign(:revenue_chart, revenue_chart_data(Analytics.monthly_revenue(opts)))
    |> assign(:revenue_by_course, revenue_by_course)
    |> assign(
      :attributed_revenue_minor,
      Enum.sum(Enum.map(revenue_by_course, & &1.revenue_minor))
    )
    |> assign(:active_learners, active_learners(course_id, user_id))
    |> assign(:module_rows, module_rows)
    |> assign(:filtered_module_rows, filter_module_rows(module_rows, module_query))
    |> assign(:module_completion_avg, average_percent(module_rows, :completion_percent))
    |> assign(:module_quiz_avg, average_percent(module_rows, :quiz_score_percent))
    |> assign(:range_label, range_label(opts))
  end

  # `module_completion_rates/1` already answers "what % of active learners
  # are eligible for cert are through this module" — since eligibility never
  # narrows between modules, that same rate *is* the retention percentage
  # used by the drop-off panel, so there's no separate retention query.
  defp build_module_rows(nil, _opts), do: []

  defp build_module_rows(course_id, opts) do
    completion_rates = Analytics.module_completion_rates(opts)
    quiz_scores = Analytics.average_quiz_scores(opts)

    course_id
    |> Catalog.get_course_with_outline!()
    |> Map.fetch!(:modules)
    |> Enum.map(fn module ->
      completion = Map.get(completion_rates, module.id)
      quiz = Map.get(quiz_scores, module.id)

      completion &&
        %{
          module_id: module.id,
          title: module.title,
          completion_percent: completion.rate_percent,
          remaining_learners: completion.completed_learners,
          quiz_score_percent: quiz && round(quiz.average_score_percent)
        }
    end)
    |> Enum.filter(& &1)
  end

  defp filter_module_rows(rows, query) do
    query = query |> to_string() |> String.trim() |> String.downcase()

    if query == "" do
      rows
    else
      Enum.filter(rows, &String.contains?(String.downcase(&1.title), query))
    end
  end

  defp average_percent(rows, key) do
    values = rows |> Enum.map(&Map.get(&1, key)) |> Enum.filter(& &1)

    case values do
      [] -> nil
      values -> round(Enum.sum(values) / length(values))
    end
  end

  defp percent_or_dash(nil), do: "—"
  defp percent_or_dash(value), do: "#{value}%"

  defp funnel_overall_conversion([%{count: 0} | _]), do: nil
  defp funnel_overall_conversion(steps), do: percent(List.last(steps).count, hd(steps).count)

  defp funnel_widget_data(steps) do
    last_index = length(steps) - 1

    steps
    |> Enum.with_index()
    |> Enum.map(fn {%{count: count} = step, index} ->
      previous_count = index > 0 && Enum.at(steps, index - 1).count

      Map.merge(step, %{
        percent_of_previous: previous_count && percent(count, previous_count),
        last?: index == last_index
      })
    end)
  end

  defp percent(_count, 0), do: 0
  defp percent(count, total), do: round(count / total * 100)

  defp student_option_label(%{name: name, email: email}) when is_binary(name) and name != "",
    do: "#{name} (#{email})"

  defp student_option_label(%{email: email}), do: email

  defp active_learners(nil, nil), do: Enrollments.count_active()

  defp active_learners(nil, user_id),
    do: user_id |> Enrollments.count_active_by_course_for_user() |> Map.values() |> Enum.sum()

  defp active_learners(course_id, nil), do: Enrollments.count_active_for_course(course_id)

  defp active_learners(course_id, user_id) do
    user_id
    |> Enrollments.count_active_by_course_for_user()
    |> Map.get(course_id, 0)
  end

  defp revenue_bar_percent(_revenue_minor, []), do: 0

  defp revenue_bar_percent(revenue_minor, rows) do
    max_revenue = rows |> Enum.map(& &1.revenue_minor) |> Enum.max()
    if max_revenue > 0, do: round(revenue_minor / max_revenue * 100), else: 0
  end

  defp retained_label([]), do: "—"

  defp retained_label(rows) do
    "#{List.last(rows).completion_percent}% retained"
  end

  defp range_label(opts) do
    case {Keyword.get(opts, :from), Keyword.get(opts, :to)} do
      {nil, nil} -> "Last 12 months"
      _ -> "Selected date range"
    end
  end

  defp revenue_chart_data(rows) do
    Enum.map(rows, fn %{month: month, revenue_minor: revenue_minor} ->
      %{
        label: Calendar.strftime(month, "%b %Y"),
        value: revenue_minor,
        value_label: compact_revenue_label(revenue_minor),
        tooltip: Payments.format_minor(revenue_minor)
      }
    end)
  end

  # Chart labels need to stay short, so amounts past 10k KES collapse to
  # "12.5K"/"1.2M" instead of the full "12,500 KES" used everywhere
  # else in the admin area (stat cards, top courses, recent payments).
  defp compact_revenue_label(amount_minor) do
    major = amount_minor / 100

    cond do
      major >= 1_000_000 -> compact_number(major / 1_000_000) <> "M KES"
      major >= 10_000 -> compact_number(major / 1_000) <> "K KES"
      true -> Payments.format_minor(amount_minor)
    end
  end

  defp compact_number(number) do
    rounded = Float.round(number, 1)

    if rounded == trunc(rounded) do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, decimals: 1)
    end
  end

  defp raw_query_params(params) do
    [
      course_id: params["course_id"],
      user_id: params["user_id"],
      from: params["from"],
      to: params["to"]
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp leaderboard_path(query_params, page) do
    params =
      query_params
      |> Keyword.put(:page, page)
      |> Enum.reject(fn
        {:page, 1} -> true
        {_key, value} -> value in [nil, ""]
      end)

    ~p"/admin/analytics?#{params}"
  end

  defp parse_id(nil), do: nil
  defp parse_id(""), do: nil

  defp parse_id(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # Inline mini progress bar for a leaderboard percentage column — lets an
  # admin spot low performers at a glance instead of reading every number.
  attr :percent, :integer, required: true

  defp rate_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <div class="h-1.5 w-16 overflow-hidden rounded-full bg-black/10">
        <div class="h-full rounded-full bg-primary" style={"width: #{@percent}%"} />
      </div>
      <span class="text-body">{@percent}%</span>
    </div>
    """
  end
end
