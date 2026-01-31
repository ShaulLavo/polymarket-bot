defmodule PolymarketBot.Repo do
  use Ecto.Repo,
    otp_app: :polymarket_bot,
    adapter: Ecto.Adapters.SQLite3
end
