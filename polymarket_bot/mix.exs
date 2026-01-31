defmodule PolymarketBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :polymarket_bot,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:ecto_sqlite3, "~> 0.18"}
    ]
  end
end
