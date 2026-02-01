defmodule PolymarketBot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Database (always started)
        PolymarketBot.Repo,
        # PubSub for LiveView
        {Phoenix.PubSub, name: PolymarketBot.PubSub}
      ]
      |> maybe_add_child(
        :start_data_collector,
        PolymarketBot.DataCollector
      )
      |> maybe_add_child(
        :start_websocket,
        PolymarketBot.WebSocket
      )
      |> maybe_add_child(
        :start_http_server,
        PolymarketBot.Endpoint
      )

    opts = [strategy: :one_for_one, name: PolymarketBot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_child(children, config_key, child) do
    if Application.get_env(:polymarket_bot, config_key, true) do
      children ++ [child]
    else
      children
    end
  end
end
