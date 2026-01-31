import Config

config :logger, level: :warning

config :polymarket_bot, PolymarketBot.Repo,
  database: "priv/test.db",
  pool: Ecto.Adapters.SQL.Sandbox
