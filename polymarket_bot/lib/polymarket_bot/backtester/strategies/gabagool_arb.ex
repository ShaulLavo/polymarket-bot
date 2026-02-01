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
  - `cost_aware_entry` - Factor in trading costs when evaluating (default: true)
  - `min_net_spread` - Minimum spread AFTER costs (default: 0.005 = 0.5%)
  """
  @behaviour PolymarketBot.Backtester.Strategy

  alias PolymarketBot.Backtester.TradingCosts

  @default_config %{
    entry_threshold: 0.02,
    position_size: 1.0,
    max_positions: 5,
    cost_aware_entry: true,
    min_net_spread: 0.005
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

    # Calculate gross spread
    total_price = yes_price + no_price
    gross_spread = 1.0 - total_price

    # Calculate net spread after costs if cost-aware mode is enabled
    {net_spread, cost_info} = calculate_net_spread(price_data, config)

    # Determine which spread threshold to use
    effective_spread =
      if config.cost_aware_entry and cost_info != nil do
        net_spread
      else
        gross_spread
      end

    # Determine minimum threshold
    min_threshold =
      if config.cost_aware_entry and cost_info != nil do
        max(config.entry_threshold, config.min_net_spread)
      else
        config.entry_threshold
      end

    cond do
      # Arbitrage opportunity: effective spread exceeds threshold and room for more positions
      effective_spread > min_threshold and length(positions) < config.max_positions ->
        position = %{
          yes_price: yes_price,
          no_price: no_price,
          total_cost: total_price,
          gross_spread: gross_spread,
          net_spread: net_spread,
          spread: effective_spread,
          cost_info: cost_info,
          entry_timestamp: price_data.timestamp
        }

        state = %{
          state
          | positions: [position | positions],
            opportunities_found: state.opportunities_found + 1,
            spreads_captured: [effective_spread | state.spreads_captured]
        }

        # Use :open_gabagool for multi-position mode, :buy for legacy
        signal =
          if Map.has_key?(price_data, :trading_costs) and price_data.trading_costs != nil do
            {:open_gabagool, config.position_size}
          else
            {:buy, config.position_size}
          end

        {signal, state}

      true ->
        {:hold, state}
    end
  end

  # Calculate net spread after trading costs
  defp calculate_net_spread(price_data, config) do
    trading_costs = Map.get(price_data, :trading_costs)

    if config.cost_aware_entry and trading_costs != nil do
      # Build market context for cost estimation
      market_context = %{
        liquidity: price_data[:liquidity] || 10_000.0,
        volume: price_data[:volume] || 1000.0,
        yes_spread: price_data[:yes_spread],
        no_spread: price_data[:no_spread]
      }

      cost_info =
        TradingCosts.estimate_gabagool_costs(
          price_data.yes_price,
          price_data.no_price,
          config.position_size,
          trading_costs,
          market_context
        )

      {cost_info.net_spread, cost_info}
    else
      # No costs configured, use gross spread
      gross_spread = 1.0 - (price_data.yes_price + price_data.no_price)
      {gross_spread, nil}
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

    # Calculate both gross and net profits
    gross_spreads = Enum.map(positions, &Map.get(&1, :gross_spread, &1.spread))
    net_spreads = Enum.map(positions, &Map.get(&1, :net_spread, &1.spread))

    gross_profit = gross_spreads |> Enum.sum() |> to_float()
    net_profit = net_spreads |> Enum.sum() |> to_float()

    total_invested =
      positions
      |> Enum.map(& &1.total_cost)
      |> Enum.sum()
      |> to_float()

    # Calculate cost impact
    cost_impact = gross_profit - net_profit

    stats = %{
      opportunities_found: state.opportunities_found,
      positions_held: total_positions,
      spreads_captured: Enum.reverse(spreads),
      avg_spread: Float.round(avg_spread, 4),
      # Gross profit (before costs)
      gross_profit: Float.round(gross_profit, 4),
      # Net profit (after costs) - this is what you actually make
      net_profit: Float.round(net_profit, 4),
      # Total trading costs
      total_cost_impact: Float.round(cost_impact, 4),
      # Legacy field for backwards compatibility
      theoretical_profit: Float.round(net_profit, 4),
      total_invested: Float.round(total_invested, 4),
      roi_percent:
        if total_invested > 0 do
          Float.round(net_profit / total_invested * 100, 2)
        else
          0.0
        end,
      gross_roi_percent:
        if total_invested > 0 do
          Float.round(gross_profit / total_invested * 100, 2)
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
