defmodule PolymarketBot.Repo.Migrations.CreatePriceSnapshots do
  use Ecto.Migration

  def change do
    create table(:price_snapshots) do
      add :market_id, :string, null: false
      add :token_id, :string
      add :yes_price, :float, null: false
      add :no_price, :float, null: false
      add :volume, :float
      add :liquidity, :float
      add :timestamp, :utc_datetime, null: false
      
      timestamps(type: :utc_datetime)
    end

    create index(:price_snapshots, [:market_id])
    create index(:price_snapshots, [:timestamp])
    create index(:price_snapshots, [:market_id, :timestamp])
  end
end
