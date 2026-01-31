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
      {:req, "~> 0.5"},  # HTTP client
      {:websockex, "~> 0.4.3"},  # WebSocket client for real-time data
      {:signet, "~> 1.5"},  # Ethereum/EIP-712 signing (for trading later)
      {:ecto_sql, "~> 3.12"},  # Database ORM
      {:ecto_sqlite3, "~> 0.18"}  # SQLite3 adapter (simple, file-based)
    ]
  end
end
