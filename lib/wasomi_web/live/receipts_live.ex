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
      <div class="px-5 py-8 lg:px-8 lg:py-10">
        <section class="rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="text-sm font-semibold uppercase tracking-wider text-primary">Billing</p>
              <h1 class="mt-2 text-3xl font-semibold text-ink sm:text-4xl">Payment receipts</h1>
              <p class="mt-2 max-w-2xl text-body">
                A record of every course payment on your account. Download a PDF for your files.
              </p>
            </div>
            <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-receipt-percent" class="h-6 w-6" />
            </span>
          </div>

          <.paginated_table
            :if={@page.entries != []}
            page={@page.page}
            total_pages={@page.total_pages}
            path_fn={&receipts_path/1}
          >
            <div class="mt-8 overflow-hidden rounded-2xl border border-black/5">
              <div
                :for={receipt <- @page.entries}
                id={"receipt-#{receipt.id}"}
                class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 px-5 py-4 last:border-b-0 sm:px-6"
              >
                <div class="min-w-0">
                  <h2 class="truncate font-semibold text-ink">{receipt.course.title}</h2>
                  <p class="mt-1 text-sm text-muted">
                    {format_date(receipt.paid_at)} · {provider_name(receipt.provider)} · Ref
                    <span class="break-all">{receipt.provider_reference}</span>
                  </p>
                </div>

                <div class="flex shrink-0 items-center gap-4">
                  <span class="font-semibold text-ink">{Payments.format_amount(receipt)}</span>
                  <.link
                    href={~p"/receipts/#{receipt.id}/download"}
                    class="inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary"
                  >
                    <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> PDF
                  </.link>
                </div>
              </div>
            </div>
          </.paginated_table>

          <div :if={@page.entries == []} id="receipts-empty" class="mt-8 py-12 text-center">
            <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-receipt-percent" class="h-7 w-7" />
            </span>
            <h2 class="mt-5 text-xl font-semibold text-ink">No receipts yet.</h2>
            <p class="mx-auto mt-2 max-w-md text-body">
              Successful course payments will show up here with a downloadable receipt.
            </p>
          </div>
        </section>
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
