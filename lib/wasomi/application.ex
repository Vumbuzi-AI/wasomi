defmodule Wasomi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WasomiWeb.Telemetry,
      Wasomi.Repo,
      {Oban, Application.fetch_env!(:wasomi, Oban)},
      {DNSCluster, query: Application.get_env(:wasomi, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Wasomi.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Wasomi.Finch},
      # Start a worker by calling: Wasomi.Worker.start_link(arg)
      # {Wasomi.Worker, arg},
      # Start to serve requests, typically the last entry
      WasomiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Wasomi.Supervisor]
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WasomiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
