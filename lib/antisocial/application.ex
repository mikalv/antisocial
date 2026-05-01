defmodule Antisocial.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AntisocialWeb.Telemetry,
      Antisocial.Repo,
      {DNSCluster, query: Application.get_env(:antisocial, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Antisocial.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Antisocial.Finch},
      Antisocial.TTLWorker,
      Antisocial.PasskeyChallenge,
      # Start to serve requests, typically the last entry
      AntisocialWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Antisocial.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AntisocialWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
