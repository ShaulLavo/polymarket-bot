import Config

config :polymarket_bot, PolymarketBot.Repo,
  database: "priv/polymarket_data.db",
  pool_size: 5

config :polymarket_bot,
  ecto_repos: [PolymarketBot.Repo]

# Phoenix Endpoint
config :polymarket_bot, PolymarketBot.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PolymarketBot.ErrorHTML],
    layout: false
  ],
  pubsub_server: PolymarketBot.PubSub,
  live_view: [signing_salt: "polymarket_lv_salt"]

# esbuild configuration
config :esbuild,
  version: "0.20.2",
  polymarket_bot: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Tailwind configuration
config :tailwind,
  version: "3.4.3",
  polymarket_bot: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
