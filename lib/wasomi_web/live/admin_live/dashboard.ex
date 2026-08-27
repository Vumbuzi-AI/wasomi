defmodule WasomiWeb.AdminLive.Dashboard do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Catalog, Enrollments, Payments}

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
     |> assign(:search, "")
     |> assign(:total_revenue_minor, Payments.total_revenue_minor())
     |> assign(:student_count, Accounts.count_users(:learner))
     |> assign(:course_count, length(courses))
     |> assign(:published_count, Catalog.count_courses(:published))
     |> assign(:active_enrollments, Enrollments.count_active())
     |> assign(:courses_with_active_enrollments, map_size(enrollments_by_course))
     |> assign(:successful_payments, Payments.count_payments(:successful))
     |> assign(:top_courses, top_courses)
     |> assign(:recent_payments, Payments.list_recent_payments(8))}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign(socket, :search, query)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:overview} current_user={@current_user}>
      <div class="w-full space-y-5 px-5 py-8 lg:px-8">
        <.page_header title="Business overview">
          <:subtitle>A live snapshot of revenue, enrollment and GS1 course activity.</:subtitle>
          <:actions>
            <.search_input value={@search} placeholder="Search courses, learners or payments" />
            <button
              type="button"
              class="group relative grid h-11 w-11 place-items-center rounded-2xl bg-ink text-white transition hover:bg-primary"
              aria-label="View report"
            >
              <.icon name="hero-document-text" class="h-5 w-5" />
              <.tooltip label="View report" />
            </button>
          </:actions>
        </.page_header>

        <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Total revenue"
            value={Payments.format_minor(@total_revenue_minor)}
            icon="hero-banknotes"
            hint={"#{@successful_payments} successful payments"}
          />
          <.stat_card
            label="Students"
            value={@student_count}
            icon="hero-users"
            hint="Registered learners"
          />
          <.stat_card
            label="Active enrollments"
            value={@active_enrollments}
            icon="hero-academic-cap"
            hint={"Across #{@courses_with_active_enrollments} #{ngettext("course", "courses", @courses_with_active_enrollments)}"}
          />
          <.stat_card
            label="Courses"
            value={@course_count}
            icon="hero-rectangle-stack"
            hint={"#{@published_count} published"}
          />
        </div>

        <div class="grid gap-4 lg:grid-cols-2">
          <%!-- Top courses --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-2xl font-semibold text-ink">Revenue</h2>
                <p class="mt-1 text-sm text-muted">Top GS1 courses by revenue</p>
              </div>
              <.link
                navigate={~p"/admin/courses"}
                class="flex items-center gap-1 text-sm font-semibold text-primary hover:text-ink"
              >
                View all <.icon name="hero-arrow-right" class="h-4 w-4" />
              </.link>
            </div>

            <div :if={@top_courses != []} class="mt-5 divide-y divide-black/5">
              <.link
                :for={{row, index} <- Enum.with_index(@top_courses, 1)}
                navigate={~p"/admin/courses/#{row.course.slug}"}
                class="flex items-center gap-4 rounded-2xl px-3 py-4 transition even:bg-surface/50 hover:bg-mint/45"
              >
                <span class="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-primary/40 text-sm font-semibold text-primary">
                  {String.pad_leading("#{index}", 2, "0")}
                </span>
                <div class="min-w-0 flex-1">
                  <p class="truncate font-medium text-ink">{row.course.title}</p>
                  <p class="mt-0.5 text-sm text-muted">{row.students} learner enrolled</p>
                </div>
                <p class="shrink-0 font-semibold text-ink">
                  {Payments.format_minor(row.revenue_minor, row.course.currency)}
                </p>
              </.link>
            </div>

            <p :if={@top_courses == []} class="mt-5 rounded-2xl bg-surface p-5 text-body">
              No courses yet. Create your first course to start selling.
            </p>
          </section>

          <%!-- Recent payments --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-2xl font-semibold text-ink">Payments</h2>
                <p class="mt-1 text-sm text-muted">Latest successful transactions</p>
              </div>
              <.link
                navigate={~p"/admin/payments"}
                class="flex items-center gap-1 text-sm font-semibold text-primary hover:text-ink"
              >
                View all <.icon name="hero-arrow-right" class="h-4 w-4" />
              </.link>
            </div>

            <div class="mt-5 flex items-center justify-between gap-4 rounded-2xl bg-ink p-5">
              <div>
                <p class="text-sm text-white/70">Total collected</p>
                <p class="mt-1 text-2xl font-semibold text-white">
                  {Payments.format_minor(@total_revenue_minor)}
                </p>
              </div>
              <span class="rounded-full border border-white/30 px-3 py-1.5 text-xs font-semibold text-white">
                {@successful_payments} {ngettext("payment", "payments", @successful_payments)}
              </span>
            </div>

            <div :if={@recent_payments != []} class="mt-5 divide-y divide-black/5">
              <div
                :for={payment <- @recent_payments}
                class="flex items-center gap-3 rounded-2xl px-3 py-4 transition even:bg-surface/50 hover:bg-mint/45"
              >
                <span class="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-primary/40 text-primary">
                  <.icon name="hero-document-text" class="h-5 w-5" />
                </span>
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-medium text-ink">
                    {payment.user && (payment.user.name || payment.user.email)}
                  </p>
                  <p class="truncate text-xs text-muted">{payment.course && payment.course.title}</p>
                </div>
                <div class="shrink-0 text-right">
                  <p class="text-sm font-semibold text-ink">{Payments.format_amount(payment)}</p>
                  <.status_badge status={payment.status} />
                </div>
              </div>
            </div>

            <p :if={@recent_payments == []} class="mt-5 rounded-2xl bg-surface p-5 text-body">
              Payments will appear here as learners check out.
            </p>
          </section>
        </div>
      </div>
    </.admin_layout>
    """
  end
end
