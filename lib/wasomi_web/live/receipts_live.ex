defmodule WasomiWeb.ReceiptsLive do
  @moduledoc """
  A learner's payment receipts — one row per successful course payment,
  each downloadable as a PDF. Moved here from the dashboard so billing has
  its own home.
  """

  use WasomiWeb, :live_view

  alias Wasomi.{Paginate, Payments, Receipts}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Receipts")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page_number = Paginate.parse_page(params["page"])
    page = Receipts.page_for_user(socket.assigns.current_user, page: page_number)

    {:noreply, assign(socket, :page, page)}
  end

  defp receipts_path(1), do: ~p"/receipts"
  defp receipts_path(page), do: ~p"/receipts?#{[page: page]}"

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:receipts} current_user={@current_user}>
      <div class="w-full px-5 py-8 lg:px-8">
        <.learner_page_header eyebrow="Billing" title="Payment receipts">
          <:subtitle>
            A record of every course payment on your account. Download a PDF for your files.
          </:subtitle>
          <:actions :if={@page.entries != []}>
            {@page.total_count} {if @page.total_count == 1, do: "receipt", else: "receipts"}
          </:actions>
        </.learner_page_header>

        <.paginated_table
          :if={@page.entries != []}
          page={@page.page}
          total_pages={@page.total_pages}
          path_fn={&receipts_path/1}
        >
          <div
            id="receipts-list"
            class="mt-8 overflow-x-auto rounded-3xl border border-black/5 bg-white shadow-card"
          >
            <table class="w-full text-left text-sm">
              <thead class="border-b border-black/5 bg-surface text-xs uppercase tracking-wide text-body">
                <tr>
                  <th class="px-6 py-4 font-semibold">Course</th>
                  <th class="px-6 py-4 font-semibold">Date</th>
                  <th class="px-6 py-4 font-semibold">Payment</th>
                  <th class="px-6 py-4 font-semibold">Amount</th>
                  <th class="px-6 py-4 font-semibold"><span class="sr-only">Receipt</span></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-black/5">
                <tr
                  :for={receipt <- @page.entries}
                  id={"receipt-#{receipt.id}"}
                  class="transition even:bg-surface/50 hover:bg-mint/45"
                >
                  <td class="px-6 py-4 font-semibold text-ink">{receipt.course.title}</td>
                  <td class="px-6 py-4 text-body">{format_date(receipt.paid_at)}</td>
                  <td class="px-6 py-4 text-body">
                    {provider_name(receipt.provider)}
                    <span class="mt-1 block break-all text-xs text-muted">
                      Ref {receipt.provider_reference}
                    </span>
                  </td>
                  <td class="px-6 py-4 font-semibold text-ink">{Payments.format_amount(receipt)}</td>
                  <td class="px-6 py-4 text-right">
                    <.link
                      href={~p"/receipts/#{receipt.id}/download"}
                      class="inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-1.5 text-xs font-semibold text-white transition hover:bg-primary"
                    >
                      <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> PDF
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.paginated_table>

        <div
          :if={@page.entries == []}
          id="receipts-empty"
          class="mt-8 rounded-3xl border border-black/5 bg-white p-8 text-center shadow-card sm:p-12"
        >
          <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
            <.icon name="hero-receipt-percent" class="h-7 w-7" />
          </span>
          <h2 class="mt-5 text-xl font-semibold text-ink">No receipts yet.</h2>
          <p class="mx-auto mt-2 max-w-md text-body">
            Successful course payments will show up here with a downloadable receipt.
          </p>
        </div>
      </div>
    </.student_layout>
    """
  end

  defp provider_name(:paystack), do: "Paystack"
  defp provider_name(:mpesa), do: "M-Pesa"
  defp provider_name(provider), do: provider |> to_string() |> String.capitalize()

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
