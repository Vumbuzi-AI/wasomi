defmodule WasomiWeb.AdminLive.Payments do
  use WasomiWeb, :live_view

  alias Wasomi.Payments

  @impl true
  def mount(_params, _session, socket) do
    {:ok, refresh_payments(socket) |> assign(:page_title, "Payments")}
  end

  @impl true
  def handle_event("reconcile", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {payment_id, ""} ->
        socket =
          payment_id
          |> Payments.verify_transaction()
          |> put_reconciliation_flash(socket)
          |> refresh_payments()

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid payment id.")}
    end
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
                <th class="px-6 py-4 font-semibold"><span class="sr-only">Actions</span></th>
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
                <td class="px-6 py-4 text-right">
                  <button
                    :if={payment.status == :pending}
                    type="button"
                    phx-click="reconcile"
                    phx-value-id={payment.id}
                    phx-disable-with="Verifying..."
                    class="rounded-full bg-dark px-4 py-1.5 text-xs font-semibold text-white transition hover:bg-primary disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Reconcile
                  </button>
                </td>
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

  defp refresh_payments(socket) do
    socket
    |> assign(:payments, Payments.list_recent_payments(100))
    |> assign(:total_revenue_minor, Payments.total_revenue_minor())
    |> assign(:successful, Payments.count_payments(:successful))
    |> assign(:pending, Payments.count_payments(:pending))
    |> assign(:failed, Payments.count_payments(:failed))
  end

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
