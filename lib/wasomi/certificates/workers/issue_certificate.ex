defmodule Wasomi.Certificates.Workers.IssueCertificate do
  @moduledoc """
  Renders, stores, persists, and announces a certificate exactly once per scope.
  """

  use Oban.Worker,
    queue: :certificates,
    max_attempts: 8,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:user_id, :type, :scope_id],
      states: :all
    ]

  alias Wasomi.Certificates
  alias Wasomi.Notifications.Workers.DeliverCertificateIssued

  def new(user_id, type, scope_id) do
    __MODULE__.new(%{
      user_id: user_id,
      type: to_string(type),
      scope_id: scope_id
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "type" => type, "scope_id" => scope_id}
      }) do
    with {:ok, type} <- parse_type(type),
         {:ok, certificate, status} <- Certificates.issue(user_id, type, scope_id) do
      if status == :created do
        :ok = Certificates.broadcast_ready(certificate)
        {:ok, _job} = Oban.insert(DeliverCertificateIssued.for_certificate(certificate.id))
      end

      :ok
    end
  end

  defp parse_type("module"), do: {:ok, :module}
  defp parse_type("course"), do: {:ok, :course}
  defp parse_type(_), do: {:error, :invalid_scope}
end
