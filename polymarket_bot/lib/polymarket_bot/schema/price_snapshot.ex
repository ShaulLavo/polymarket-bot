defmodule PolymarketBot.Schema.PriceSnapshot do
  @moduledoc """
  Schema for price snapshots - the core data for backtesting.

  Stores YES/NO prices at a point in time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "price_snapshots" do
    # Polymarket market ID
    field(:market_id, :string)
    # CLOB token ID
    field(:token_id, :string)
    field(:yes_price, :float)
    field(:no_price, :float)
    field(:volume, :float)
    field(:liquidity, :float)
    field(:timestamp, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:market_id, :token_id, :yes_price, :no_price, :volume, :liquidity, :timestamp])
    |> validate_required([:market_id, :yes_price, :no_price, :timestamp])
  end
end
