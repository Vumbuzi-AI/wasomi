defmodule WasomiWeb.AdminLive.Analytics do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Paginate, Payments}
  alias Wasomi.Catalog.Analytics

  @page_size 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Analytics")
     |> assign(:courses, Catalog.list_courses())
     |> assign(:active_tab, :overview)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    opts =
      [
        course_id: parse_id(params["course_id"]),
        from: parse_date(params["from"]),
        to: parse_date(params["to"])
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    filter_form =
      to_form(
        %{
          "course_id" => params["course_id"] || "",
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
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
        <.page_header title="Analytics">
          <:subtitle>
            Conversion, revenue, and course performance, filterable by course and date range.
          </:subtitle>
        </.page_header>

        <section class="rounded-3xl border border-black/5 bg-white p-6">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-2 rounded-full border border-black/5 bg-neutral-50 p-1.5">
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

            <div class="flex flex-wrap items-center gap-4">
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
          </div>

          <.form
            id="filter-form"
            for={@filter_form}
            phx-change="filter"
            class="mt-5 flex flex-wrap items-end gap-4 border-b border-black/5 pb-6"
          >
            <div class="min-w-[220px] flex-1">
              <.input
                field={@filter_form[:course_id]}
                type="select"
                label="Course"
                prompt="All courses"
                options={Enum.map(@courses, &{&1.title, &1.id})}
              />
            </div>
            <.input field={@filter_form[:from]} type="date" label="From" max="today" />
            <.input field={@filter_form[:to]} type="date" label="To" max="today" />
          </.form>

          <div :if={@active_tab == :overview} class="mt-6 space-y-10">
            <div>
              <div class="flex flex-wrap items-baseline justify-between gap-2">
                <h3 class="text-base font-semibold text-ink">Conversion funnel</h3>
                <p :if={@funnel_overall_conversion} class="text-sm text-body">
                  <span class="font-semibold text-primary">{@funnel_overall_conversion}%</span>
                  overall, checkout to certificate
                </p>
              </div>
              <div class="mt-4 flex flex-wrap items-stretch gap-3">
                <div :for={step <- @funnel} class="contents">
                  <div class="min-w-[140px] flex-1 rounded-2xl border border-black/5 bg-white p-4 text-center shadow-sm">
                    <p class="text-xs font-semibold uppercase tracking-wide text-body">
                      {step.step}
                    </p>
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
            </div>

            <div>
              <h3 class="text-base font-semibold text-ink">Course leaderboard</h3>
              <p class="mt-1 text-xs text-body">Richest-first. Click a course for detail.</p>
              <.paginated_table
                page={@scorecards_page.page}
                total_pages={@scorecards_page.total_pages}
                path_fn={&leaderboard_path(@export_query, &1)}
              >
                <div class="mt-4 overflow-x-auto rounded-2xl border border-black/5">
                  <table class="w-full text-left text-sm">
                    <thead class="border-b border-black/5 bg-neutral-50 text-xs font-semibold uppercase tracking-wide text-body">
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
                        class="transition hover:bg-neutral-50/60"
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
            </div>
          </div>

          <div :if={@active_tab == :revenue} class="mt-6">
            <div class="rounded-2xl border border-black/5 bg-white p-5 shadow-sm">
              <.column_chart
                title="Monthly revenue"
                data={@revenue_chart}
                empty_message="No successful payments in range."
              />
            </div>
          </div>
        </section>
      </div>
    </.admin_layout>
    """
  end

  defp assign_analytics(socket, opts) do
    funnel = Analytics.funnel(opts)
    scorecards = Analytics.course_scorecards(opts)

    socket
    |> assign(:funnel, funnel_widget_data(funnel))
    |> assign(:funnel_overall_conversion, funnel_overall_conversion(funnel))
    |> assign(
      :scorecards_page,
      Paginate.paginate_list(scorecards, socket.assigns.page_number, @page_size)
    )
    |> assign(:revenue_chart, revenue_chart_data(Analytics.monthly_revenue(opts)))
  end

  # First step is "Checkout started", last is "Certified" — nil (rather
  # than a misleading 0%) when nobody's even started a checkout yet, so
  # the header omits the stat instead of showing a hollow "0%".
  defp funnel_overall_conversion([%{count: 0} | _]), do: nil
  defp funnel_overall_conversion(steps), do: percent(List.last(steps).count, hd(steps).count)

  # Enriches each funnel step with its conversion rate from the previous
  # step (nil for the first step, which has nothing to convert from) and
  # whether it's the last step, so the template doesn't need `Enum.with_index`
  # to know when to skip the trailing arrow between cards.
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
  # "12.5K"/"1.2M" instead of the full "12,500.00 KES" used everywhere
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
    [course_id: params["course_id"], from: params["from"], to: params["to"]]
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
