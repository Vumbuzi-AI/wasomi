defmodule WasomiWeb.AdminLive.Students do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Enrollments, Payments}

  @impl true
  def mount(_params, _session, socket) do
    enrollments_by_user = Enrollments.count_active_by_user()
    revenue_by_user = Payments.revenue_minor_by_user()

    rows =
      Accounts.list_users()
      |> Enum.map(fn user ->
        %{
          user: user,
          courses: Map.get(enrollments_by_user, user.id, 0),
          spent_minor: Map.get(revenue_by_user, user.id, 0)
        }
      end)

    {:ok,
     socket
     |> assign(:page_title, "Students")
     |> assign(:rows, rows)
     |> assign(:learner_count, Accounts.count_users(:learner))
     |> assign(:admin_count, Accounts.count_users(:admin))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:students} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
        <.page_header eyebrow="People" title="Students">
          <:subtitle>Everyone who has registered on Wasomi and what they have enrolled in.</:subtitle>
        </.page_header>

        <div class="grid gap-5 sm:grid-cols-3">
          <.stat_card label="Total users" value={length(@rows)} icon="hero-users" />
          <.stat_card label="Learners" value={@learner_count} icon="hero-user" />
          <.stat_card label="Admins" value={@admin_count} icon="hero-shield-check" />
        </div>

        <div :if={@rows != []} class="overflow-hidden rounded-3xl border border-black/5 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-black/5 text-xs uppercase tracking-wide text-muted">
              <tr>
                <th class="px-6 py-4 font-semibold">Student</th>
                <th class="px-6 py-4 font-semibold">Phone</th>
                <th class="px-6 py-4 font-semibold">Role</th>
                <th class="px-6 py-4 font-semibold">Courses</th>
                <th class="px-6 py-4 font-semibold">Total spent</th>
                <th class="px-6 py-4 font-semibold">Joined</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-black/5">
              <tr :for={row <- @rows} class="transition hover:bg-soft/60">
                <td class="px-6 py-4">
                  <.link
                    navigate={~p"/admin/students/#{row.user.id}"}
                    class="font-medium text-dark hover:text-primary"
                  >
                    {row.user.name || "Learner"}
                  </.link>
                  <p class="text-xs text-muted">{row.user.email}</p>
                </td>
                <td class="px-6 py-4 text-body">{row.user.phone || "—"}</td>
                <td class="px-6 py-4"><.status_badge status={row.user.role} /></td>
                <td class="px-6 py-4 text-body">{row.courses}</td>
                <td class="px-6 py-4 font-semibold text-dark">
                  {Payments.format_minor(row.spent_minor)}
                </td>
                <td class="px-6 py-4 text-body">{format_date(row.user.inserted_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          :if={@rows == []}
          class="rounded-3xl border border-black/5 bg-white p-12 text-center text-body"
        >
          No students have registered yet.
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
