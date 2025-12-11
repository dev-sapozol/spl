defmodule Spl.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias Spl.InboxEmail

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SplWeb.Telemetry,
      Spl.Repo,
      InboxEmail,
      {DNSCluster, query: Application.get_env(:spl, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Spl.PubSub},
      SplWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Spl.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SplWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
