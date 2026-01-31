defmodule PolymarketBot.Schema.OrderbookSnapshot do
  @moduledoc """
  Schema for order book snapshots.
  
  Stores full order book state at a point in time.
  Critical for backtesting execution strategies.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "orderbook_snapshots" do
    field :token_id, :string
    field :market_id, :string
    field :bids, :string  # JSON array of {price, size} tuples
    field :asks, :string  # JSON array of {price, size} tuples
    field :best_bid, :float
    field :best_ask, :float
    field :spread, :float
    field :timestamp, :utc_datetime
    
    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:token_id, :market_id, :bids, :asks, :best_bid, :best_ask, :spread, :timestamp])
    |> validate_required([:token_id, :bids, :asks, :timestamp])
  end
end
