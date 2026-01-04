defmodule HelpdeskCommander.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HelpdeskCommanderWeb.Telemetry,
      HelpdeskCommander.Repo,
      {DNSCluster, query: Application.get_env(:helpdesk_commander, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: HelpdeskCommander.PubSub},
      # Start a worker by calling: HelpdeskCommander.Worker.start_link(arg)
      # {HelpdeskCommander.Worker, arg},
      # Start to serve requests, typically the last entry
      HelpdeskCommanderWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HelpdeskCommander.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HelpdeskCommanderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
