defmodule Wasomi.Payments.Workers.ReconcilePendingPayments do
  use Oban.Worker,
    queue: :payments,
    max_attempts: 5,
    unique: [period: 55, fields: [:worker]]

  alias Wasomi.Payments
  alias Wasomi.Payments.Workers.ProcessPaystackWebhook

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Payments.list_stale_pending_payments()
    |> Enum.each(fn payment ->
      %{"reference" => payment.provider_reference, "event" => %{"event" => "reconciliation"}}
      |> ProcessPaystackWebhook.new()
      |> Oban.insert()
    end)

    :ok
  end
end
