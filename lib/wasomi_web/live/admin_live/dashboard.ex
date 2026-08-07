defmodule WasomiWeb.AdminLive.Dashboard do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Catalog, Enrollments, Payments}
  alias Wasomi.Catalog.Analytics

  @impl true
  def mount(_params, _session, socket) do
    revenue_by_course = Payments.revenue_minor_by_course()
    enrollments_by_course = Enrollments.count_active_by_course()

    courses = Catalog.list_courses()

    top_courses =
      courses
      |> Enum.map(fn course ->
        %{
          course: course,
          students: Map.get(enrollments_by_course, course.id, 0),
          revenue_minor: Map.get(revenue_by_course, course.id, 0)
        }
      end)
      |> Enum.sort_by(& &1.revenue_minor, :desc)
      |> Enum.take(5)

    {:ok,
     socket
     |> assign(:page_title, "Overview")
     |> assign(:total_revenue_minor, Payments.total_revenue_minor())
     |> assign(:student_count, Accounts.count_users(:learner))
     |> assign(:course_count, length(courses))
     |> assign(:published_count, Catalog.count_courses(:published))
     |> assign(:active_enrollments, Enrollments.count_active())
     |> assign(:successful_payments, Payments.count_payments(:successful))
     |> assign(:top_courses, top_courses)
     |> assign(:recent_payments, Payments.list_recent_payments(8))
     |> assign(:courses, courses)}
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
     |> assign_analytics(opts)}
  end

  @impl true
  def handle_event("filter", %{"filter" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin?#{raw_query_params(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:overview} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-10 px-5 py-10 lg:px-10">
        <.page_header eyebrow="Dashboard" title="Business overview">
          <:subtitle>A live snapshot of revenue, enrollment and catalog health.</:subtitle>
          <:actions>
            <.link
              navigate={~p"/admin/courses/new"}
              class="group inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
            >
              New course
              <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
                <.icon name="hero-plus-mini" class="h-4 w-4" />
              </span>
            </.link>
          </:actions>
        </.page_header>

        <div class="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Total revenue"
            value={Payments.format_minor(@total_revenue_minor)}
            icon="hero-banknotes"
            hint={"#{@successful_payments} successful payments"}
          />
          <.stat_card label="Students" value={@student_count} icon="hero-users" />
          <.stat_card label="Active enrollments" value={@active_enrollments} icon="hero-academic-cap" />
          <.stat_card
            label="Courses"
            value={@course_count}
            icon="hero-rectangle-stack"
            hint={"#{@published_count} published"}
          />
        </div>

        <section class="rounded-3xl border border-black/5 bg-white p-6">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-xl font-semibold text-dark">Analytics</h2>
            <div class="flex items-center gap-4">
              <.link
                :if={@has_filters?}
                patch={~p"/admin"}
                class="text-sm font-medium text-primary hover:text-dark"
              >
                Clear filters
              </.link>
              <span class="text-sm font-medium text-muted">Export CSV:</span>
              <.link
                href={~p"/admin/exports/enrollments?#{@export_query}"}
                class="text-sm font-medium text-primary hover:text-dark"
              >
                Enrollments
              </.link>
              <.link
                href={~p"/admin/exports/payments?#{@export_query}"}
                class="text-sm font-medium text-primary hover:text-dark"
              >
                Payments
              </.link>
              <.link
                href={~p"/admin/exports/quiz_results?#{@export_query}"}
                class="text-sm font-medium text-primary hover:text-dark"
              >
                Quiz results
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

          <div class="mt-6 grid gap-8 lg:grid-cols-2">
            <.bar_chart
              title="Module completion rate"
              data={@completion_chart}
              empty_message="No modules with lectures yet."
            />
            <.bar_chart
              title="Average quiz score"
              data={@quiz_score_chart}
              empty_message="No quiz submissions in range."
            />
            <.bar_chart
              title="Video drop-off (earliest first)"
              data={@dropoff_chart}
              empty_message="No in-progress viewers in range."
            />
            <.column_chart
              title="Monthly revenue"
              data={@revenue_chart}
              empty_message="No successful payments in range."
            />
          </div>
        </section>

        <div class="grid gap-6 lg:grid-cols-5">
          <%!-- Top courses --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6 lg:col-span-3">
            <div class="flex items-center justify-between">
              <h2 class="text-xl font-semibold text-dark">Top courses by revenue</h2>
              <.link
                navigate={~p"/admin/courses"}
                class="text-sm font-medium text-primary hover:text-dark"
              >
                View all →
              </.link>
            </div>

            <div :if={@top_courses != []} class="mt-5 divide-y divide-black/5">
              <.link
                :for={row <- @top_courses}
                navigate={~p"/admin/courses/#{row.course.id}"}
                class="flex items-center justify-between gap-4 py-4 first:pt-0 last:pb-0 transition hover:opacity-80"
              >
                <div class="min-w-0">
                  <p class="truncate font-medium text-dark">{row.course.title}</p>
                  <p class="mt-0.5 text-sm text-muted">{row.students} students enrolled</p>
                </div>
                <p class="shrink-0 font-semibold text-dark">
                  {Payments.format_minor(row.revenue_minor, row.course.currency)}
                </p>
              </.link>
            </div>

            <p :if={@top_courses == []} class="mt-5 rounded-2xl bg-soft p-5 text-body">
              No courses yet. Create your first course to start selling.
            </p>
          </section>

          <%!-- Recent payments --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6 lg:col-span-2">
            <div class="flex items-center justify-between">
              <h2 class="text-xl font-semibold text-dark">Recent payments</h2>
              <.link
                navigate={~p"/admin/payments"}
                class="text-sm font-medium text-primary hover:text-dark"
              >
                All →
              </.link>
            </div>

            <div :if={@recent_payments != []} class="mt-5 space-y-4">
              <div :for={payment <- @recent_payments} class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <p class="truncate text-sm font-medium text-dark">
                    {payment.user && (payment.user.name || payment.user.email)}
                  </p>
                  <p class="truncate text-xs text-muted">{payment.course && payment.course.title}</p>
                </div>
                <div class="shrink-0 text-right">
                  <p class="text-sm font-semibold text-dark">{Payments.format_amount(payment)}</p>
                  <.status_badge status={payment.status} />
                </div>
              </div>
            </div>

            <p :if={@recent_payments == []} class="mt-5 rounded-2xl bg-soft p-5 text-body">
              Payments will appear here as learners check out.
            </p>
          </section>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp assign_analytics(socket, opts) do
    socket
    |> assign(:completion_chart, completion_chart_data(Analytics.module_completion_rates(opts)))
    |> assign(:quiz_score_chart, quiz_score_chart_data(Analytics.average_quiz_scores(opts)))
    |> assign(:dropoff_chart, dropoff_chart_data(Analytics.video_dropoff_seconds(opts)))
    |> assign(:revenue_chart, revenue_chart_data(Analytics.monthly_revenue(opts)))
  end

  defp completion_chart_data(rates) do
    rates
    |> Map.values()
    |> Enum.sort_by(& &1.rate_percent, :desc)
    |> Enum.map(&%{label: &1.title, value: &1.rate_percent, value_label: "#{&1.rate_percent}%"})
  end

  defp quiz_score_chart_data(scores) do
    scores
    |> Map.values()
    |> Enum.sort_by(& &1.average_score_percent, :desc)
    |> Enum.map(fn row ->
      rounded = round(row.average_score_percent)
      %{label: row.quiz_title, value: row.average_score_percent, value_label: "#{rounded}%"}
    end)
  end

  defp dropoff_chart_data(lectures) do
    Enum.map(
      lectures,
      &%{label: &1.title, value: &1.dropoff_percent, value_label: "#{&1.dropoff_percent}%"}
    )
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
  # "12.5K"/"1.2M" instead of the full "12,500.00 KES" used everywhere
  # else on the dashboard (stat cards, top courses, recent payments).
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
end
