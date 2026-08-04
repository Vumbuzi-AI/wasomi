defmodule Wasomi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @chrome_candidates ~w(chromium-browser chromium google-chrome chrome
                        /usr/bin/chromium-browser /usr/bin/chromium /usr/bin/google-chrome
                        /opt/google/chrome/chrome)

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
      maybe_chromic_pdf(),
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

  defp maybe_chromic_pdf do
    if Application.get_env(:wasomi, :start_chromic_pdf, true) do
      case chrome_executable() do
        nil ->
          Logger.warning(
            "No Chrome/Chromium executable found; skipping ChromicPDF startup. " <>
              "Certificate PDF rendering will be unavailable until CHROME_EXECUTABLE is set " <>
              "or a browser is installed at one of the standard paths."
          )

          nil

        executable ->
          {ChromicPDF, chrome_executable: executable, no_sandbox: no_sandbox?()}
      end
    end
  end

  defp chrome_executable do
    case System.get_env("CHROME_EXECUTABLE") do
      path when is_binary(path) and path != "" -> path
      _ -> Enum.find_value(@chrome_candidates, &System.find_executable/1)
    end
  end

  # Sandboxed by default — Chrome's sandbox is a real defense-in-depth layer
  # against a renderer exploit escaping to the host process. Only disable it
  # where the deployment target requires it (commonly: running as root in a
  # container without the extra privileges the sandbox needs).
  defp no_sandbox?, do: System.get_env("CHROME_NO_SANDBOX") in ["1", "true"]
end
