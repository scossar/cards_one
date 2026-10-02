defmodule CardsOne.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    pubsub = System.get_env("ELIXIRKIT_PUBSUB")

    children = [
      CardsOneWeb.Telemetry,
      CardsOne.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:cards_one, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:cards_one, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CardsOne.PubSub},
      # Start a worker by calling: CardsOne.Worker.start_link(arg)
      # {CardsOne.Worker, arg},
      # Start to serve requests, typically the last entry
      {ElixirKit.PubSub, connect: pubsub || :ignore, on_exit: fn -> System.stop() end},
      CardsOneWeb.Endpoint,
      {Task,
       fn ->
         if pubsub do
           ElixirKit.PubSub.broadcast("messages", "ready")
         end
       end}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CardsOne.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CardsOneWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
