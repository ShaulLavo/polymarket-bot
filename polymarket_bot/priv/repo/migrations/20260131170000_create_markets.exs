defmodule PolymarketBot.Repo.Migrations.CreateMarkets do
  use Ecto.Migration

  def change do
    create table(:markets) do
      add :polymarket_id, :string, null: false
      add :question, :text, null: false
      add :slug, :string
      add :event_id, :string
      add :condition_id, :string
      add :yes_token_id, :string
      add :no_token_id, :string
      add :outcomes, :text  # JSON
      add :active, :boolean, default: true
      add :closed, :boolean, default: false
      
      timestamps()
    end

    create unique_index(:markets, [:polymarket_id])
    create index(:markets, [:slug])
    create index(:markets, [:active])
  end
end
