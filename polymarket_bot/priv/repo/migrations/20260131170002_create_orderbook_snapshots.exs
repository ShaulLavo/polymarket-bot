defmodule PolymarketBot.Repo.Migrations.CreateOrderbookSnapshots do
  use Ecto.Migration

  def change do
    create table(:orderbook_snapshots) do
      add :token_id, :string, null: false
      add :market_id, :string
      add :bids, :text, null: false  # JSON array
      add :asks, :text, null: false  # JSON array
      add :best_bid, :float
      add :best_ask, :float
      add :spread, :float
      add :timestamp, :utc_datetime, null: false
      
      timestamps(type: :utc_datetime)
    end

    create index(:orderbook_snapshots, [:token_id])
    create index(:orderbook_snapshots, [:timestamp])
    create index(:orderbook_snapshots, [:token_id, :timestamp])
  end
end
