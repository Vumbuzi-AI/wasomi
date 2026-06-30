defmodule Wasomi.Payments.Workers.ProcessPaystackWebhook do
  use Oban.Worker,
    queue: :payments,
    max_attempts: 10,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:reference]]

  alias Wasomi.Payments

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"reference" => reference, "event" => event}}) do
    _ = Payments.record_webhook_event(reference, event)

    case Payments.process_paystack_reference(reference) do
      {:ok, _result} -> :ok
      {:error, {:payment_failed, _payment}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
