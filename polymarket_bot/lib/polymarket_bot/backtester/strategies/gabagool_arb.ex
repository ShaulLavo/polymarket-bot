defmodule PolymarketBot.Backtester.Strategies.GabagoolArb do
  @moduledoc """
  Gabagool Arbitrage Strategy for Polymarket prediction markets.

  Strategy logic:
  - In Polymarket, YES + NO tokens must equal $1.00 at resolution
  - When YES + NO prices sum to less than $1.00, there's a risk-free arbitrage
  - Buy both sides when spread exceeds threshold
  - Hold to resolution for guaranteed profit

  Example:
  - YES = $0.48, NO = $0.50, Total = $0.98
  - Spread = $1.00 - $0.98 = $0.02 (2% guaranteed profit)
  - At resolution: receive $1.00, paid $0.98, profit = $0.02

  Configuration:
  - `entry_threshold` - Minimum spread to enter (default: 0.02 = 2%)
  - `position_size` - Size of each arbitrage position (default: 1.0)
  - `max_positions` - Maximum concurrent positions (default: 5)
  """
  @behaviour PolymarketBot.Backtester.Strategy

  @default_config %{
    entry_threshold: 0.02,
    position_size: 1.0,
    max_positions: 5
  }

  @impl true
  def name, do: "Gabagool Arbitrage"

  @impl true
  def default_config, do: @default_config

  @impl true
  def init(config) do
    config = Map.merge(@default_config, config || %{})

    state = %{
      config: config,
      positions: [],
      opportunities_found: 0,
      spreads_captured: [],
      trades: []
    }

    {:ok, state}
  end

  @impl true
  def on_price(price_data, state) do
    %{yes_price: yes_price, no_price: no_price} = price_data
    %{config: config, positions: positions} = state

    total_price = yes_price + no_price
    spread = 1.0 - total_price

    cond do
      # Arbitrage opportunity: spread exceeds threshold and we have room for more positions
      spread > config.entry_threshold and length(positions) < config.max_positions ->
        position = %{
          yes_price: yes_price,
          no_price: no_price,
          total_cost: total_price,
          spread: spread,
          entry_timestamp: price_data.timestamp
        }

        state = %{
          state
          | positions: [position | positions],
            opportunities_found: state.opportunities_found + 1,
            spreads_captured: [spread | state.spreads_captured]
        }

        {{:buy, config.position_size}, state}

      true ->
        {:hold, state}
    end
  end

  @impl true
  def on_complete(state) do
    %{positions: positions, spreads_captured: spreads} = state

    total_positions = length(positions)

    avg_spread =
      if total_positions > 0 do
        Enum.sum(spreads) / total_positions
      else
        0.0
      end

    theoretical_profit =
      positions
      |> Enum.map(& &1.spread)
      |> Enum.sum()
      |> to_float()

    total_invested =
      positions
      |> Enum.map(& &1.total_cost)
      |> Enum.sum()
      |> to_float()

    stats = %{
      opportunities_found: state.opportunities_found,
      positions_held: total_positions,
      spreads_captured: Enum.reverse(spreads),
      avg_spread: Float.round(avg_spread, 4),
      theoretical_profit: Float.round(theoretical_profit, 4),
      total_invested: Float.round(total_invested, 4),
      roi_percent:
        if total_invested > 0 do
          Float.round(theoretical_profit / total_invested * 100, 2)
        else
          0.0
        end,
      positions: Enum.reverse(positions)
    }

    {:ok, stats}
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1
end
