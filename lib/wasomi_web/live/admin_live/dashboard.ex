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
     |> assign(:page_title, "Admin overview")
     |> assign(:total_revenue_minor, Payments.total_revenue_minor())
     |> assign(:student_count, Accounts.count_users(:learner))
     |> assign(:course_count, length(courses))
     |> assign(:published_count, Catalog.count_courses(:published))
     |> assign(:active_enrollments, Enrollments.count_active())
     |> assign(:successful_payments, Payments.count_payments(:successful))
     |> assign(:top_courses, top_courses)
     |> assign(:recent_payments, Payments.list_recent_payments(8))}
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
end
