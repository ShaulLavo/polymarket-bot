defmodule PolymarketBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :polymarket_bot,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PolymarketBot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      # HTTP client
      {:req, "~> 0.5"},
      # WebSocket client for real-time data
      {:websockex, "~> 0.5.1"},
      # Ethereum/EIP-712 signing (for trading later)
      {:signet, "~> 1.5"},
      # Database ORM
      {:ecto_sql, "~> 3.12"},
      # SQLite3 adapter (simple, file-based)
      {:ecto_sqlite3, "~> 0.18"},
      # Phoenix LiveView
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      # Assets
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      # HTTP server adapter
      {:bandit, "~> 1.5"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind polymarket_bot", "esbuild polymarket_bot"],
      "assets.deploy": [
        "tailwind polymarket_bot --minify",
        "esbuild polymarket_bot --minify",
        "phx.digest"
      ]
    ]
  end
end
