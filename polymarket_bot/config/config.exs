import Config

config :polymarket_bot, PolymarketBot.Repo,
  database: "priv/polymarket_data.db",
  pool_size: 5

config :polymarket_bot,
  ecto_repos: [PolymarketBot.Repo]

# Import environment specific config
import_config "#{config_env()}.exs"
