defmodule WasomiWeb.AdminLive.Students do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Enrollments, Paginate, Payments}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Students")
     |> assign(:total_users, Accounts.count_users())
     |> assign(:learner_count, Accounts.count_users(:learner))
     |> assign(:admin_count, Accounts.count_users(:admin))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["q"] || ""
    page_number = Paginate.parse_page(params["page"])

    enrollments_by_user = Enrollments.count_active_by_user()
    revenue_by_user = Payments.revenue_minor_by_user()

    page = Accounts.list_users_page(search: search, page: page_number)

    rows =
      Enum.map(page.entries, fn user ->
        %{
          user: user,
          courses: Map.get(enrollments_by_user, user.id, 0),
          spent_minor: Map.get(revenue_by_user, user.id, 0)
        }
      end)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:rows, rows)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: students_path(query))}
  end

  defp students_path(search, page \\ 1) do
    params =
      %{q: search, page: page}
      |> Enum.reject(fn
        {:page, 1} -> true
        {_key, value} -> value in [nil, ""]
      end)

    ~p"/admin/students?#{params}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:students} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
        <.page_header title="Students">
          <:subtitle>Everyone who has registered on Wasomi and what they have enrolled in.</:subtitle>
          <:actions>
            <.search_input value={@search} placeholder="Search name, email or phone" />
            <.link
              href={~p"/admin/exports/enrollments"}
              class="group relative grid h-11 w-11 place-items-center rounded-full border border-black/10 bg-white text-ink transition hover:border-primary hover:text-primary"
              aria-label="Export all enrollments as CSV"
            >
              <.icon name="hero-document-arrow-down" class="h-5 w-5" />
              <.tooltip label="Export all enrollments as CSV" />
            </.link>
          </:actions>
        </.page_header>

        <div class="grid gap-5 sm:grid-cols-3">
          <.stat_card
            label="Total users"
            value={@total_users}
            icon="hero-users"
            hint="Registered Wasomi accounts"
          />
          <.stat_card
            label="Learners"
            value={@learner_count}
            icon="hero-user"
            hint="Learner accounts"
          />
          <.stat_card
            label="Admins"
            value={@admin_count}
            icon="hero-shield-check"
            hint="Admin accounts"
          />
        </div>

        <div class="rounded-[2rem] border border-black/5 bg-white p-6 shadow-sm lg:p-8">
          <.paginated_table
            page={@page.page}
            total_pages={@page.total_pages}
            path_fn={&students_path(@search, &1)}
          >
            <div :if={@rows != []} class="overflow-x-auto">
              <table class="w-full text-left text-sm">
                <thead class="border-b border-black/5 text-xs uppercase tracking-wide text-body">
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
                  <tr :for={row <- @rows} class="transition hover:bg-neutral-50/60">
                    <td class="px-6 py-4">
                      <.link
                        navigate={~p"/admin/students/#{row.user.id}"}
                        class="font-medium text-ink hover:text-primary"
                      >
                        {row.user.name || "Learner"}
                      </.link>
                      <p class="text-xs text-muted">{row.user.email}</p>
                    </td>
                    <td class="px-6 py-4 text-body">{row.user.phone || "—"}</td>
                    <td class="px-6 py-4"><.status_badge status={row.user.role} /></td>
                    <td class="px-6 py-4 text-body">{row.courses}</td>
                    <td class="px-6 py-4 font-semibold text-ink">
                      {Payments.format_minor(row.spent_minor)}
                    </td>
                    <td class="px-6 py-4 text-body">{format_date(row.user.inserted_at)}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div
              :if={@rows == [] and @total_users == 0}
              class="rounded-2xl bg-neutral-50 p-12 text-center text-body"
            >
              No students have registered yet.
            </div>

            <div
              :if={@rows == [] and @total_users > 0}
              class="rounded-2xl bg-neutral-50 p-12 text-center text-body"
            >
              No students match "{@search}".
            </div>
          </.paginated_table>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
