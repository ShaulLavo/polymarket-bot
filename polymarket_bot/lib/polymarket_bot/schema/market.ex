defmodule PolymarketBot.Schema.Market do
  @moduledoc """
  Schema for Polymarket markets.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "markets" do
    field(:polymarket_id, :string)
    field(:question, :string)
    field(:slug, :string)
    field(:event_id, :string)
    field(:condition_id, :string)
    field(:yes_token_id, :string)
    field(:no_token_id, :string)
    # JSON string
    field(:outcomes, :string)
    field(:active, :boolean)
    field(:closed, :boolean)

    timestamps()
  end

  def changeset(market, attrs) do
    market
    |> cast(attrs, [
      :polymarket_id,
      :question,
      :slug,
      :event_id,
      :condition_id,
      :yes_token_id,
      :no_token_id,
      :outcomes,
      :active,
      :closed
    ])
    |> validate_required([:polymarket_id, :question])
    |> unique_constraint(:polymarket_id)
  end
end
