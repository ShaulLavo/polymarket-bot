import Config

config :logger, level: :warning

config :polymarket_bot, PolymarketBot.Repo,
  database: "priv/test.db",
  pool: Ecto.Adapters.SQL.Sandbox

# Disable HTTP server, data collector, and websocket in tests
config :polymarket_bot,
  start_http_server: false,
  start_data_collector: false,
  start_websocket: false
