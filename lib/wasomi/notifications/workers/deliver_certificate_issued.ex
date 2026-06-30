defmodule Wasomi.Notifications.Workers.DeliverCertificateIssued do
  @moduledoc false

  use Oban.Worker,
    queue: :mailers,
    max_attempts: 10,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:certificate_id]]

  alias Wasomi.Accounts.UserNotifier
  alias Wasomi.Certificates
  alias Wasomi.Repo

  def for_certificate(certificate_id), do: new(%{certificate_id: certificate_id})

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"certificate_id" => certificate_id}}) do
    certificate =
      certificate_id
      |> Certificates.get_certificate!()
      |> Repo.preload([:user, :course, :module])

    UserNotifier.deliver_certificate_issued(certificate)
  end
end
