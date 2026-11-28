defmodule Pkg.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PkgWeb.Telemetry,
      Pkg.Repo,
      {DNSCluster, query: Application.get_env(:pkg, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pkg.PubSub},
      # Start a worker by calling: Pkg.Worker.start_link(arg)
      # {Pkg.Worker, arg},
      # Start to serve requests, typically the last entry
      PkgWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pkg.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PkgWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
