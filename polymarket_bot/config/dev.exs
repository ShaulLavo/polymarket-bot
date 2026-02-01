import Config

config :logger, level: :debug

# Development endpoint config
config :polymarket_bot, PolymarketBot.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev_secret_key_base_at_least_64_bytes_long_for_development_only_not_production",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:polymarket_bot, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:polymarket_bot, ~w(--watch)]}
  ]

# Live reload configuration
config :polymarket_bot, PolymarketBot.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/polymarket_bot_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Development recompilation
config :phoenix_live_reload, :dirs, ["lib"]
