defmodule Wasomi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        WasomiWeb.Telemetry,
        Wasomi.Repo,
        {Oban, Application.fetch_env!(:wasomi, Oban)},
        {DNSCluster, query: Application.get_env(:wasomi, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Wasomi.PubSub},
        {Task.Supervisor, name: Wasomi.TaskSupervisor},
        WasomiWeb.Presence,
        # Start the Finch HTTP client for sending emails
        {Finch, name: Wasomi.Finch}
      ] ++
        chromic_pdf_child() ++
        [
          # Start a worker by calling: Wasomi.Worker.start_link(arg)
          # {Wasomi.Worker, arg},
          # Start to serve requests, typically the last entry
          WasomiWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Wasomi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Headless-Chrome pool for PDF/PNG rendering (certificates, receipts).
  # Off in test and skippable in dev via `config :wasomi, :start_chromic_pdf`,
  # so neither CI nor a browser-less dev box has to run Chrome.
  defp chromic_pdf_child do
    if Application.get_env(:wasomi, :start_chromic_pdf, false) do
      [{ChromicPDF, Application.get_env(:wasomi, :chromic_pdf_options, [])}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WasomiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
