defmodule PolymarketBot.Backtester.TradingCosts do
  @moduledoc """
  Models realistic trading costs for backtesting.

  Costs modeled:
  - Slippage: Price impact based on order size and liquidity
  - Fees: Polymarket trading fees
  - Spread: Bid-ask spread impact on execution

  ## Configuration

      %{
        # Slippage model
        slippage_factor: 0.001,         # 0.1% base slippage per unit
        slippage_liquidity_scale: true, # Scale slippage by available liquidity

        # Fee structure
        maker_fee: 0.0,                 # Maker fee (currently 0% on Polymarket)
        taker_fee: 0.0,                 # Taker fee (model as 0% for now)

        # Spread simulation
        spread_enabled: true,
        default_spread: 0.01,           # 1 cent default if no orderbook data
        spread_from_data: true          # Use actual spread from orderbook snapshots
      }

  ## Usage

      # Calculate execution price with all costs
      {:ok, exec_price, costs} = TradingCosts.apply_costs(
        price: 0.50,
        side: :buy,
        size: 100.0,
        config: %{slippage_factor: 0.001},
        context: %{liquidity: 10000.0, spread: 0.02}
      )
  """

  @default_config %{
    # Slippage model: linear impact based on position size relative to liquidity
    slippage_factor: 0.001,
    slippage_liquidity_scale: true,
    slippage_min_liquidity: 1000.0,

    # Fee structure
    maker_fee: 0.0,
    taker_fee: 0.0,

    # Spread simulation
    spread_enabled: true,
    default_spread: 0.01,
    spread_from_data: true
  }

  @doc """
  Returns the default trading costs configuration.
  """
  def default_config, do: @default_config

  @doc """
  Merges user config with defaults.
  """
  def merge_config(user_config) do
    Map.merge(@default_config, user_config || %{})
  end

  @doc """
  Apply all trading costs to a price and return the execution price.

  ## Parameters

  - `price` - The quoted mid-price
  - `side` - `:buy` or `:sell`
  - `size` - Order size in dollars
  - `config` - Trading costs configuration
  - `context` - Market context with liquidity, spread data

  ## Returns

  `{:ok, execution_price, cost_breakdown}` where cost_breakdown is:

      %{
        base_price: float(),
        execution_price: float(),
        slippage_pct: float(),
        slippage_amount: float(),
        spread_cost: float(),
        fee_amount: float(),
        total_cost: float()
      }
  """
  def apply_costs(price, side, size, config, context \\ %{}) do
    config = merge_config(config)

    # Calculate each cost component
    {slippage_pct, slippage_amount} = calculate_slippage(price, side, size, config, context)
    spread_cost = calculate_spread_cost(price, side, config, context)
    fee_amount = calculate_fees(price * size, side, config)

    # Calculate execution price
    execution_price =
      case side do
        :buy ->
          # Buys: price goes up (pay more)
          price + slippage_amount + spread_cost

        :sell ->
          # Sells: price goes down (receive less)
          price - slippage_amount - spread_cost
      end

    # Ensure price stays in valid range [0, 1] for prediction markets
    execution_price = max(0.001, min(0.999, execution_price))

    total_cost = abs(execution_price - price) * size + fee_amount

    cost_breakdown = %{
      base_price: price,
      execution_price: execution_price,
      slippage_pct: slippage_pct,
      slippage_amount: slippage_amount,
      spread_cost: spread_cost,
      fee_amount: fee_amount,
      total_cost: total_cost
    }

    {:ok, execution_price, cost_breakdown}
  end

  @doc """
  Calculate slippage based on order size and market liquidity.

  Uses a linear impact model:
    slippage_pct = base_factor * (size / liquidity)

  For illiquid markets or large orders, slippage can be significant.
  """
  def calculate_slippage(price, _side, size, config, context) do
    base_factor = config[:slippage_factor] || 0.001
    liquidity = context[:liquidity] || config[:slippage_min_liquidity] || 1000.0
    scale_by_liquidity = config[:slippage_liquidity_scale] != false

    slippage_pct =
      if scale_by_liquidity and liquidity > 0 do
        # Slippage increases with order size relative to liquidity
        base_factor * (size / liquidity)
      else
        base_factor
      end

    # Cap slippage at 10% to prevent unrealistic values
    slippage_pct = min(slippage_pct, 0.10)
    slippage_amount = price * slippage_pct

    {slippage_pct, slippage_amount}
  end

  @doc """
  Calculate the spread cost (half the bid-ask spread for crossing).

  When buying, you pay the ask (mid + half spread).
  When selling, you receive the bid (mid - half spread).
  """
  def calculate_spread_cost(price, _side, config, context) do
    spread_enabled = config[:spread_enabled] != false

    if spread_enabled do
      spread =
        cond do
          # Use explicit spread from context if available
          config[:spread_from_data] != false and is_number(context[:spread]) ->
            context[:spread]

          # Use bid/ask if available
          is_number(context[:bid]) and is_number(context[:ask]) ->
            context[:ask] - context[:bid]

          # Fall back to default spread
          true ->
            config[:default_spread] || 0.01
        end

      # We cross half the spread
      half_spread = spread / 2

      # Ensure spread cost doesn't exceed the price
      min(half_spread, price * 0.5)
    else
      0.0
    end
  end

  @doc """
  Calculate trading fees based on notional value.

  Polymarket currently has 0% maker fees and varying taker fees.
  This model allows configuring both.
  """
  def calculate_fees(notional_value, _side, config) do
    # For now, assume taker orders (market orders)
    fee_rate = config[:taker_fee] || 0.0
    notional_value * fee_rate
  end

  @doc """
  Estimate round-trip costs for entering and exiting a position.

  Useful for strategies to evaluate if a trade is profitable after costs.
  """
  def estimate_round_trip_costs(entry_price, exit_price, size, config, context \\ %{}) do
    config = merge_config(config)

    {:ok, entry_exec_price, entry_costs} =
      apply_costs(entry_price, :buy, size, config, context)

    {:ok, exit_exec_price, exit_costs} =
      apply_costs(exit_price, :sell, size, config, context)

    total_cost = entry_costs.total_cost + exit_costs.total_cost

    # Effective spread (what you lose to costs)
    effective_spread = entry_exec_price - entry_price + (exit_price - exit_exec_price)

    %{
      entry_execution_price: entry_exec_price,
      exit_execution_price: exit_exec_price,
      entry_costs: entry_costs,
      exit_costs: exit_costs,
      total_cost: total_cost,
      effective_spread: effective_spread,
      cost_as_pct_of_position: total_cost / (entry_price * size) * 100
    }
  end

  @doc """
  Estimate costs for Gabagool arbitrage (buying both YES and NO).

  For arbitrage, we buy both sides, so we need to calculate costs for:
  - Buying YES token
  - Buying NO token

  The total cost reduces the arbitrage spread.
  """
  def estimate_gabagool_costs(yes_price, no_price, size, config, context \\ %{}) do
    config = merge_config(config)

    # Context for YES token
    yes_context =
      Map.merge(context, %{
        spread: context[:yes_spread],
        bid: context[:yes_bid],
        ask: context[:yes_ask]
      })

    # Context for NO token
    no_context =
      Map.merge(context, %{
        spread: context[:no_spread],
        bid: context[:no_bid],
        ask: context[:no_ask]
      })

    {:ok, yes_exec_price, yes_costs} =
      apply_costs(yes_price, :buy, size, config, yes_context)

    {:ok, no_exec_price, no_costs} =
      apply_costs(no_price, :buy, size, config, no_context)

    # Gross spread (theoretical profit)
    gross_spread = 1.0 - (yes_price + no_price)

    # Actual entry cost with slippage and spread
    actual_entry_cost = yes_exec_price + no_exec_price

    # Net spread after costs
    net_spread = 1.0 - actual_entry_cost

    # Total dollar costs
    total_cost = yes_costs.total_cost + no_costs.total_cost

    %{
      yes_execution_price: yes_exec_price,
      no_execution_price: no_exec_price,
      actual_entry_cost: actual_entry_cost,
      gross_spread: gross_spread,
      net_spread: net_spread,
      spread_erosion: gross_spread - net_spread,
      total_cost: total_cost,
      yes_costs: yes_costs,
      no_costs: no_costs,
      profitable: net_spread > 0
    }
  end
end
