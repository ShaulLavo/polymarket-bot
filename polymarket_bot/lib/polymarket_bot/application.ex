defmodule PolymarketBot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      PolymarketBot.Repo,
      
      # Data collector (collects and persists Polymarket data)
      PolymarketBot.DataCollector,
      
      # HTTP server
      {Plug.Cowboy, scheme: :http, plug: PolymarketBot.Router, options: [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: PolymarketBot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
