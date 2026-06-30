defmodule WasomiWeb.AdminLive.Payments do
  use WasomiWeb, :live_view

  alias Wasomi.Payments

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Payments")
     |> assign(:payments, Payments.list_recent_payments(100))
     |> assign(:total_revenue_minor, Payments.total_revenue_minor())
     |> assign(:successful, Payments.count_payments(:successful))
     |> assign(:pending, Payments.count_payments(:pending))
     |> assign(:failed, Payments.count_payments(:failed))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:payments} current_user={@current_user}>
      <div class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10">
        <.page_header eyebrow="Billing" title="Payments">
          <:subtitle>Every checkout attempt and the revenue it generated.</:subtitle>
        </.page_header>

        <div class="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Total revenue"
            value={Payments.format_minor(@total_revenue_minor)}
            icon="hero-banknotes"
          />
          <.stat_card label="Successful" value={@successful} icon="hero-check-circle" />
          <.stat_card label="Pending" value={@pending} icon="hero-clock" />
          <.stat_card label="Failed" value={@failed} icon="hero-x-circle" />
        </div>

        <div :if={@payments != []} class="overflow-hidden rounded-3xl border border-black/5 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-black/5 text-xs uppercase tracking-wide text-muted">
              <tr>
                <th class="px-6 py-4 font-semibold">Student</th>
                <th class="px-6 py-4 font-semibold">Course</th>
                <th class="px-6 py-4 font-semibold">Provider</th>
                <th class="px-6 py-4 font-semibold">Reference</th>
                <th class="px-6 py-4 font-semibold">Amount</th>
                <th class="px-6 py-4 font-semibold">Status</th>
                <th class="px-6 py-4 font-semibold">Date</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-black/5">
              <tr :for={payment <- @payments} class="transition hover:bg-soft/60">
                <td class="px-6 py-4">
                  <.link
                    :if={payment.user}
                    navigate={~p"/admin/students/#{payment.user_id}"}
                    class="font-medium text-dark hover:text-primary"
                  >
                    {payment.user.name || payment.user.email}
                  </.link>
                  <span :if={!payment.user} class="text-muted">—</span>
                </td>
                <td class="px-6 py-4 text-body">{payment.course && payment.course.title}</td>
                <td class="px-6 py-4 capitalize text-body">{payment.provider}</td>
                <td class="px-6 py-4 text-xs text-muted">{payment.provider_reference}</td>
                <td class="px-6 py-4 font-semibold text-dark">{Payments.format_amount(payment)}</td>
                <td class="px-6 py-4"><.status_badge status={payment.status} /></td>
                <td class="px-6 py-4 text-body">{format_date(payment.inserted_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          :if={@payments == []}
          class="rounded-3xl border border-black/5 bg-white p-12 text-center text-body"
        >
          No payments have been recorded yet.
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
