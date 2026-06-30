defmodule WasomiWeb.AdminLive.StudentShow do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Enrollments, Payments}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_user!(id)
    payments = Payments.list_payments_for_user(user.id)

    spent_minor =
      payments
      |> Enum.filter(&(&1.status == :successful))
      |> Enum.map(& &1.amount_minor)
      |> Enum.sum()

    {:ok,
     socket
     |> assign(:page_title, user.name || user.email)
     |> assign(:user, user)
     |> assign(:enrollments, Enrollments.list_active_for_user(user))
     |> assign(:payments, payments)
     |> assign(:spent_minor, spent_minor)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:students} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
        <.link
          navigate={~p"/admin/students"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to students
        </.link>

        <div class="flex flex-wrap items-center gap-4">
          <span class="grid h-16 w-16 shrink-0 place-items-center rounded-full bg-mint text-2xl font-semibold uppercase text-primary">
            {String.first(@user.name || @user.email)}
          </span>
          <div>
            <h1 class="text-3xl font-semibold text-dark">{@user.name || "Learner"}</h1>
            <p class="text-body">{@user.email}</p>
            <div class="mt-2 flex flex-wrap items-center gap-3 text-sm text-muted">
              <span :if={@user.phone}>{@user.phone}</span>
              <.status_badge status={@user.role} />
              <span>Joined {format_date(@user.inserted_at)}</span>
            </div>
          </div>
        </div>

        <div class="grid gap-5 sm:grid-cols-3">
          <.stat_card
            label="Total spent"
            value={Payments.format_minor(@spent_minor)}
            icon="hero-banknotes"
          />
          <.stat_card label="Active courses" value={length(@enrollments)} icon="hero-academic-cap" />
          <.stat_card
            label="Email confirmed"
            value={if @user.confirmed_at, do: "Yes", else: "No"}
            icon="hero-check-badge"
          />
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <%!-- Enrolled courses --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6">
            <h2 class="text-xl font-semibold text-dark">Enrolled courses</h2>

            <div :if={@enrollments != []} class="mt-5 divide-y divide-black/5">
              <.link
                :for={enrollment <- @enrollments}
                navigate={~p"/admin/courses/#{enrollment.course_id}"}
                class="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0 transition hover:opacity-80"
              >
                <div class="min-w-0">
                  <p class="truncate font-medium text-dark">{enrollment.course.title}</p>
                  <p class="text-xs text-muted">Enrolled {format_date(enrollment.activated_at)}</p>
                </div>
                <.icon name="hero-chevron-right-mini" class="h-4 w-4 shrink-0 text-muted" />
              </.link>
            </div>

            <p :if={@enrollments == []} class="mt-5 rounded-2xl bg-soft p-5 text-body">
              This learner has no active enrollments.
            </p>
          </section>

          <%!-- Payment history --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6">
            <h2 class="text-xl font-semibold text-dark">Payment history</h2>

            <div :if={@payments != []} class="mt-5 divide-y divide-black/5">
              <div :for={payment <- @payments} class="py-3 first:pt-0 last:pb-0">
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0">
                    <p class="truncate font-medium text-dark">
                      {payment.course && payment.course.title}
                    </p>
                    <p class="text-xs text-muted">
                      {format_date(payment.inserted_at)} · {payment.provider_reference}
                    </p>
                  </div>
                  <div class="shrink-0 text-right">
                    <p class="font-semibold text-dark">{Payments.format_amount(payment)}</p>
                    <.status_badge status={payment.status} />
                  </div>
                </div>
              </div>
            </div>

            <p :if={@payments == []} class="mt-5 rounded-2xl bg-soft p-5 text-body">
              No payments recorded for this learner.
            </p>
          </section>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
