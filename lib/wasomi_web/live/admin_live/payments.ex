defmodule WasomiWeb.AdminLive.Payments do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Enrollments, Payments}
  alias Wasomi.Catalog.Analytics
  alias Wasomi.Paginate
  alias Wasomi.Payments.Payment

  @status_values Ecto.Enum.values(Payment, :status)
  @sort_values ~w(date reference learner course amount status)a
  @page_size 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Payments")
     |> assign(:status_values, @status_values)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:tab, parse_tab(params["tab"]))
      |> assign(:status_filter, parse_status(params["status"]))
      |> assign(:search, params["q"] || "")
      |> assign(:page_number, Paginate.parse_page(params["page"]))
      |> assign(:sort_by, parse_sort_by(params["sort_by"]))
      |> assign(:sort_dir, parse_sort_dir(params["sort_dir"]))
      |> assign(:chart_from, parse_date(params["from"]))
      |> assign(:chart_to, parse_date(params["to"]))
      |> load_tab()

    {:noreply, socket}
  end

  defp parse_tab("revenue"), do: :revenue
  defp parse_tab(_), do: :payments

  defp parse_status(value), do: Enum.find(@status_values, &(Atom.to_string(&1) == value))

  defp parse_sort_by(value), do: Enum.find(@sort_values, :date, &(Atom.to_string(&1) == value))
  defp parse_sort_dir("asc"), do: :asc
  defp parse_sort_dir(_), do: :desc

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp load_tab(%{assigns: %{tab: :payments}} = socket) do
    page =
      Payments.list_payments_page(
        status: socket.assigns.status_filter,
        search: socket.assigns.search,
        sort_by: socket.assigns.sort_by,
        sort_dir: socket.assigns.sort_dir,
        page: socket.assigns.page_number,
        page_size: @page_size
      )

    socket
    |> assign(:payments_page, page)
    |> assign(:total_transactions, Payments.count_payments())
    |> assign(:successful, Payments.count_payments(:successful))
    |> assign(:pending, Payments.count_payments(:pending))
    |> assign(:failed, Payments.count_payments(:failed))
  end

  defp load_tab(%{assigns: %{tab: :revenue}} = socket) do
    revenue_by_course = Payments.revenue_minor_by_course()
    enrolled_by_course = Enrollments.count_by_course()
    paid_by_course = Payments.count_successful_by_course()
    last_paid_by_course = Payments.last_paid_at_by_course()

    rows =
      Catalog.list_courses(search: socket.assigns.search)
      |> Enum.map(fn course ->
        %{
          course: course,
          enrolled: Map.get(enrolled_by_course, course.id, 0),
          paid: Map.get(paid_by_course, course.id, 0),
          revenue_minor: Map.get(revenue_by_course, course.id, 0),
          last_paid_at: Map.get(last_paid_by_course, course.id)
        }
      end)
      |> Enum.sort_by(& &1.revenue_minor, :desc)

    gross_revenue_minor = Payments.total_revenue_minor()
    paid_enrolments = Payments.count_payments(:successful)

    chart_opts = [from: socket.assigns.chart_from, to: socket.assigns.chart_to]

    revenue_chart_rows =
      chart_opts
      |> Analytics.revenue_by_course()
      |> filter_revenue_rows(socket.assigns.search)

    socket
    |> assign(:revenue_page, Paginate.paginate_list(rows, socket.assigns.page_number, @page_size))
    |> assign(:gross_revenue_minor, gross_revenue_minor)
    |> assign(:paid_enrolments, paid_enrolments)
    |> assign(:average_payment_minor, average(gross_revenue_minor, paid_enrolments))
    |> assign(:courses_with_revenue, map_size(revenue_by_course))
    |> assign(
      :revenue_trend_chart,
      revenue_trend_chart_config(Analytics.monthly_revenue(chart_opts))
    )
    |> assign(
      :revenue_by_course_chart,
      revenue_by_course_chart_config(revenue_chart_rows)
    )
  end

  defp filter_revenue_rows(rows, search) when search in [nil, ""], do: rows

  defp filter_revenue_rows(rows, search) do
    search = String.downcase(search)
    Enum.filter(rows, &String.contains?(String.downcase(&1.title), search))
  end

  defp average(_total, 0), do: 0
  defp average(total, count), do: div(total, count)

  # Chart.js config maps are JSON-encoded and handed to the `Chart` JS hook
  # as-is, so every value here must be JSON-safe (no functions) — this is
  # why axis tick formatting stays plain numbers instead of currency strings.
  defp revenue_trend_chart_config(rows) do
    %{
      type: "line",
      data: %{
        labels: Enum.map(rows, &Calendar.strftime(&1.month, "%b %Y")),
        datasets: [
          %{
            label: "Revenue (KES)",
            data: Enum.map(rows, &((&1.revenue_minor || 0) / 100)),
            borderColor: "#f97316",
            backgroundColor: "rgba(249, 115, 22, 0.15)",
            pointBackgroundColor: "#f97316",
            pointRadius: 4,
            pointHoverRadius: 6,
            borderWidth: 2,
            tension: 0.35,
            fill: true
          }
        ]
      },
      options: %{
        responsive: true,
        maintainAspectRatio: false,
        plugins: %{legend: %{display: false}},
        scales: %{
          y: %{beginAtZero: true, grid: %{color: "rgba(0, 0, 0, 0.05)"}},
          x: %{grid: %{display: false}}
        }
      }
    }
  end

  defp revenue_by_course_chart_config(rows) do
    top_rows = Enum.take(rows, 8)

    %{
      type: "bar",
      data: %{
        labels: Enum.map(top_rows, & &1.title),
        datasets: [
          %{
            label: "Revenue (KES)",
            data: Enum.map(top_rows, &((&1.revenue_minor || 0) / 100)),
            backgroundColor: "#012c6a",
            borderRadius: 6,
            maxBarThickness: 48
          }
        ]
      },
      options: %{
        responsive: true,
        maintainAspectRatio: false,
        plugins: %{legend: %{display: false}},
        scales: %{
          y: %{beginAtZero: true, grid: %{color: "rgba(0, 0, 0, 0.05)"}},
          x: %{grid: %{display: false}}
        }
      }
    }
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         payments_path(socket.assigns.tab,
           status: socket.assigns.status_filter,
           search: query,
           sort_by: socket.assigns.sort_by,
           sort_dir: socket.assigns.sort_dir
         )
     )}
  end

  def handle_event("filter_chart_dates", %{"from" => from, "to" => to}, socket) do
    {:noreply,
     push_patch(socket,
       to: payments_path(:revenue, search: socket.assigns.search, from: from, to: to)
     )}
  end

  def handle_event("reconcile", %{"id" => id}, socket) do
    case id |> String.trim() |> Integer.parse() do
      {payment_id, ""} ->
        socket =
          payment_id
          |> Payments.verify_transaction(socket.assigns.current_user)
          |> put_reconciliation_flash(socket)
          |> load_tab()

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid payment id.")}
    end
  end

  # Sorting resets to page 1, same as changing the search or status filter.
  defp sort_path(status, search, sort_by, sort_dir) do
    payments_path(:payments, status: status, search: search, sort_by: sort_by, sort_dir: sort_dir)
  end

  defp payments_path(tab, opts \\ []) do
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search, "")
    page = Keyword.get(opts, :page, 1)
    sort_by = Keyword.get(opts, :sort_by, :date)
    sort_dir = Keyword.get(opts, :sort_dir, :desc)
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    params =
      %{
        tab: tab,
        status: status,
        q: search,
        page: page,
        sort_by: sort_by,
        sort_dir: sort_dir,
        from: from,
        to: to
      }
      |> Enum.reject(fn
        {:tab, :payments} -> true
        {:page, 1} -> true
        {:sort_by, :date} -> true
        {:sort_dir, :desc} -> true
        {_key, value} -> value in [nil, ""]
      end)

    ~p"/admin/payments?#{params}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:payments} current_user={@current_user}>
      <div class="w-full space-y-5 px-5 py-8 lg:px-8">
        <.page_header title="Payments and revenue">
          <:subtitle>Review course revenue and learner payment attempts.</:subtitle>
          <:actions>
            <.search_input value={@search} placeholder={search_placeholder(@tab)} debounce={300} />
            <.link
              href={~p"/admin/exports/payments"}
              class="group relative grid h-11 w-11 place-items-center rounded-full border border-black/10 bg-white text-ink transition hover:border-primary hover:text-primary"
              aria-label="Export all payments as CSV"
            >
              <.icon name="hero-document-arrow-down" class="h-5 w-5" />
              <.tooltip label="Export all payments as CSV" />
            </.link>
          </:actions>
        </.page_header>

        <div class="grid grid-cols-2 overflow-hidden rounded-2xl border border-black/5 bg-surface p-1">
          <.link
            patch={payments_path(:payments)}
            class={[
              "rounded-xl py-2.5 text-center text-sm font-medium transition",
              tab_class(@tab == :payments)
            ]}
          >
            Payments
          </.link>
          <.link
            patch={payments_path(:revenue)}
            class={[
              "rounded-xl py-2.5 text-center text-sm font-medium transition",
              tab_class(@tab == :revenue)
            ]}
          >
            Revenue
          </.link>
        </div>

        <div :if={@tab == :payments} class="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Total transactions"
            value={@total_transactions}
            icon="hero-credit-card"
            hint="All checkout attempts"
          />
          <.stat_card
            label="Successful"
            value={@successful}
            icon="hero-check-circle"
            hint="Completed transactions"
          />
          <.stat_card label="Pending" value={@pending} icon="hero-clock" hint="Awaiting confirmation" />
          <.stat_card
            label="Failed"
            value={@failed}
            icon="hero-x-circle"
            hint="Unsuccessful attempts"
          />
        </div>

        <div :if={@tab == :revenue} class="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Gross revenue"
            value={Payments.format_minor(@gross_revenue_minor)}
            icon="hero-banknotes"
          />
          <.stat_card
            label="Paid enrolments"
            value={@paid_enrolments}
            icon="hero-user"
            hint="Learners with completed payments"
          />
          <.stat_card
            label="Average payment"
            value={Payments.format_minor(@average_payment_minor)}
            icon="hero-calculator"
          />
          <.stat_card
            label="Courses with revenue"
            value={@courses_with_revenue}
            icon="hero-rectangle-stack"
          />
        </div>

        <div :if={@tab == :revenue} class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-ink">Revenue charts</h2>
              <p class="mt-1 text-sm text-body">Filter the charts by payment date range.</p>
            </div>
            <form phx-change="filter_chart_dates" class="flex flex-wrap items-end gap-3">
              <label class="text-xs font-semibold uppercase tracking-wide text-body">
                From
                <input
                  type="date"
                  name="from"
                  value={@chart_from}
                  max={Date.utc_today()}
                  class="mt-1 block rounded-xl border border-black/10 px-3 py-2 text-sm text-ink focus:border-primary focus:outline-none"
                />
              </label>
              <label class="text-xs font-semibold uppercase tracking-wide text-body">
                To
                <input
                  type="date"
                  name="to"
                  value={@chart_to}
                  max={Date.utc_today()}
                  class="mt-1 block rounded-xl border border-black/10 px-3 py-2 text-sm text-ink focus:border-primary focus:outline-none"
                />
              </label>
              <.link
                :if={@chart_from || @chart_to}
                patch={payments_path(:revenue, search: @search)}
                class="pb-2 text-sm font-medium text-primary hover:text-ink"
              >
                Clear
              </.link>
            </form>
          </div>

          <div class="mt-6 grid gap-6 lg:grid-cols-2">
            <div>
              <h3 class="text-sm font-semibold text-ink">Revenue trend</h3>
              <p class="text-xs text-body">Successful payments by month.</p>
              <div class="mt-3 h-72">
                <canvas
                  id="revenue-trend-chart"
                  phx-hook="Chart"
                  data-config={Jason.encode!(@revenue_trend_chart)}
                >
                </canvas>
              </div>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-ink">Revenue by course</h3>
              <p class="text-xs text-body">Top 8 courses by successful revenue.</p>
              <div class="mt-3 h-72">
                <canvas
                  id="revenue-by-course-chart"
                  phx-hook="Chart"
                  phx-update="ignore"
                  data-config={Jason.encode!(@revenue_by_course_chart)}
                >
                </canvas>
              </div>
            </div>
          </div>
        </div>

        <div
          :if={@tab == :payments}
          class="rounded-3xl border border-black/5 bg-white p-6 shadow-card"
        >
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-ink">Payment transactions</h2>
              <p class="mt-1 text-sm text-body">Every checkout attempt and its current status.</p>
            </div>
            <span class="rounded-full border border-primary/30 bg-mint px-3 py-1 text-xs font-semibold text-primary">
              {@payments_page.total_count} {ngettext(
                "record",
                "records",
                @payments_page.total_count
              )}
            </span>
          </div>

          <div class="mt-5 flex flex-wrap gap-2">
            <.link
              patch={
                payments_path(:payments, search: @search, sort_by: @sort_by, sort_dir: @sort_dir)
              }
              class={[
                "rounded-full px-4 py-2 text-sm font-medium transition",
                status_pill_class(@status_filter == nil)
              ]}
            >
              All statuses
            </.link>
            <.link
              :for={status <- @status_values}
              patch={
                payments_path(:payments,
                  status: status,
                  search: @search,
                  sort_by: @sort_by,
                  sort_dir: @sort_dir
                )
              }
              class={[
                "rounded-full px-4 py-2 text-sm font-medium transition",
                status_pill_class(@status_filter == status)
              ]}
            >
              {String.capitalize(to_string(status))}
            </.link>
          </div>

          <.paginated_table
            page={@payments_page.page}
            total_pages={@payments_page.total_pages}
            path_fn={
              &payments_path(:payments,
                status: @status_filter,
                search: @search,
                sort_by: @sort_by,
                sort_dir: @sort_dir,
                page: &1
              )
            }
          >
            <div :if={@payments_page.entries != []} class="mt-6 overflow-x-auto">
              <table class="w-full text-left text-sm">
                <thead class="border-b border-black/5 bg-surface text-xs uppercase tracking-wide text-body">
                  <tr>
                    <.sortable_th
                      label="Learner"
                      field={:learner}
                      current_sort_by={@sort_by}
                      current_sort_dir={@sort_dir}
                      path_fn={&sort_path(@status_filter, @search, &1, &2)}
                    />
                    <.sortable_th
                      label="Course"
                      field={:course}
                      current_sort_by={@sort_by}
                      current_sort_dir={@sort_dir}
                      path_fn={&sort_path(@status_filter, @search, &1, &2)}
                    />
                    <th class="px-6 py-4 font-semibold">Provider</th>
                    <.sortable_th
                      label="Amount"
                      field={:amount}
                      current_sort_by={@sort_by}
                      current_sort_dir={@sort_dir}
                      path_fn={&sort_path(@status_filter, @search, &1, &2)}
                    />
                    <.sortable_th
                      label="Date"
                      field={:date}
                      current_sort_by={@sort_by}
                      current_sort_dir={@sort_dir}
                      path_fn={&sort_path(@status_filter, @search, &1, &2)}
                    />
                    <.sortable_th
                      label="Status"
                      field={:status}
                      current_sort_by={@sort_by}
                      current_sort_dir={@sort_dir}
                      path_fn={&sort_path(@status_filter, @search, &1, &2)}
                    />
                    <th class="px-6 py-4 font-semibold"><span class="sr-only">Actions</span></th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-black/5">
                  <tr
                    :for={payment <- @payments_page.entries}
                    class="transition even:bg-surface/50 hover:bg-mint/45"
                  >
                    <td class="px-6 py-4">
                      <.link
                        :if={payment.user}
                        navigate={~p"/admin/students/#{payment.user_id}"}
                        class="font-medium text-ink hover:text-primary"
                      >
                        {payment.user.name || payment.user.email}
                      </.link>
                      <span :if={!payment.user} class="text-muted">—</span>
                    </td>
                    <td class="px-6 py-4 text-body">{payment.course && payment.course.title}</td>
                    <td class="px-6 py-4 text-body">
                      <span class="capitalize">{payment.provider}</span>
                      <span class="mt-1 block text-xs text-muted">{payment.provider_reference}</span>
                    </td>
                    <td class="px-6 py-4 font-semibold text-ink">
                      {Payments.format_amount(payment)}
                    </td>
                    <td class="px-6 py-4 text-body">{format_date(payment.inserted_at)}</td>
                    <td class="px-6 py-4"><.status_badge status={payment.status} /></td>
                    <td class="px-6 py-4 text-right">
                      <button
                        :if={payment.status == :pending}
                        type="button"
                        phx-click="reconcile"
                        phx-value-id={payment.id}
                        phx-disable-with="Verifying..."
                        class="rounded-full bg-ink px-4 py-1.5 text-xs font-semibold text-white transition hover:bg-primary disabled:cursor-not-allowed disabled:opacity-40"
                      >
                        Reconcile
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div
              :if={@payments_page.entries == [] and @total_transactions == 0}
              class="mt-6 rounded-2xl bg-surface p-12 text-center text-body"
            >
              No payments have been recorded yet.
            </div>

            <div
              :if={@payments_page.entries == [] and @total_transactions > 0}
              class="mt-6 rounded-2xl bg-surface p-12 text-center text-body"
            >
              No payments match the current search or status filter.
            </div>
          </.paginated_table>
        </div>

        <div :if={@tab == :revenue} class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-ink">Course revenue</h2>
              <p class="mt-1 text-sm text-body">Revenue grouped by course.</p>
            </div>
            <span class="rounded-full border border-primary/30 bg-mint px-3 py-1 text-xs font-semibold text-primary">
              {@revenue_page.total_count} {ngettext("record", "records", @revenue_page.total_count)}
            </span>
          </div>

          <.paginated_table
            page={@revenue_page.page}
            total_pages={@revenue_page.total_pages}
            path_fn={
              &payments_path(:revenue, search: @search, from: @chart_from, to: @chart_to, page: &1)
            }
          >
            <div :if={@revenue_page.entries != []} class="mt-6 overflow-x-auto">
              <table class="w-full text-left text-sm">
                <thead class="border-b border-black/5 bg-surface text-xs uppercase tracking-wide text-body">
                  <tr>
                    <th class="px-6 py-4 font-semibold">Course</th>
                    <th class="px-6 py-4 font-semibold">Enrolled</th>
                    <th class="px-6 py-4 font-semibold">Paid</th>
                    <th class="px-6 py-4 font-semibold">Gross revenue</th>
                    <th class="px-6 py-4 font-semibold">Last payment</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-black/5">
                  <tr
                    :for={row <- @revenue_page.entries}
                    class="transition even:bg-surface/50 hover:bg-mint/45"
                  >
                    <td class="px-6 py-4">
                      <.link
                        navigate={~p"/admin/courses/#{row.course.slug}"}
                        class="font-medium text-ink hover:text-primary"
                      >
                        {row.course.title}
                      </.link>
                    </td>
                    <td class="px-6 py-4 text-body">{row.enrolled}</td>
                    <td class="px-6 py-4 text-body">{row.paid}</td>
                    <td class="px-6 py-4 font-semibold text-ink">
                      {Payments.format_minor(row.revenue_minor, row.course.currency)}
                    </td>
                    <td class="px-6 py-4 text-body">{format_date(row.last_paid_at)}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div
              :if={@revenue_page.entries == []}
              class="mt-6 rounded-2xl bg-surface p-12 text-center text-body"
            >
              No courses match the current search.
            </div>
          </.paginated_table>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp search_placeholder(:payments), do: "Search learner, course or reference"
  defp search_placeholder(:revenue), do: "Search courses"

  defp tab_class(true), do: "bg-ink text-white"
  defp tab_class(false), do: "text-body hover:text-ink"

  defp status_pill_class(true), do: "bg-ink text-white"

  defp status_pill_class(false),
    do: "border border-black/10 bg-white text-body hover:border-primary hover:text-primary"

  defp put_reconciliation_flash({:ok, %{verification: verification}}, socket) do
    put_flash(socket, :info, "Payment verified as successful. " <> provider_message(verification))
  end

  defp put_reconciliation_flash({:error, {:provider_declined, verification}}, socket) do
    put_flash(
      socket,
      :error,
      "Provider reports this payment was not successful. " <> provider_message(verification)
    )
  end

  defp put_reconciliation_flash({:error, {:already_failed, _payment}}, socket) do
    put_flash(socket, :error, "This payment was already marked failed.")
  end

  defp put_reconciliation_flash({:error, :payment_not_found}, socket) do
    put_flash(socket, :error, "This payment no longer exists.")
  end

  defp put_reconciliation_flash({:error, :forbidden}, socket) do
    put_flash(socket, :error, "You are not authorized to reconcile payments.")
  end

  defp put_reconciliation_flash({:error, :reference_mismatch}, socket) do
    put_flash(
      socket,
      :error,
      "Verification failed: the provider reference does not match this payment."
    )
  end

  defp put_reconciliation_flash({:error, :amount_mismatch}, socket) do
    put_flash(socket, :error, "Verification failed: the amount does not match this payment.")
  end

  defp put_reconciliation_flash({:error, :currency_mismatch}, socket) do
    put_flash(socket, :error, "Verification failed: the currency does not match this payment.")
  end

  defp put_reconciliation_flash({:error, reason}, socket) do
    put_flash(
      socket,
      :error,
      "Could not verify this payment with the provider: #{inspect(reason)}."
    )
  end

  defp provider_message(%{"gateway_response" => response})
       when is_binary(response) and response != "" do
    "Provider response: #{response}."
  end

  defp provider_message(%{"status" => status}) when is_binary(status) and status != "" do
    "Provider status: #{status}."
  end

  defp provider_message(_verification), do: ""

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
