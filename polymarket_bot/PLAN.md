# Backtester Enhancement Plan

## Overview

This plan enhances the backtester with realistic trading simulation features for Gabagool arbitrage on BTC 15-minute markets. The current implementation uses ideal execution assumptions; we'll add slippage, fees, spread simulation, and proper multi-position support.

**Scope**: Backtester engine only (no UI - separate PR)

---

## Current State Analysis

### Backtester (`lib/polymarket_bot/backtester.ex`)
- Single-position equity tracking: `{equity_list, position, entry_price, position_size, capital_at_entry}`
- No transaction cost modeling
- Instant fills at exact prices
- Gabagool strategy tracks multiple positions internally, but backtester only handles one

### Gabagool Strategy (`lib/polymarket_bot/backtester/strategies/gabagool_arb.ex`)
- Tracks multiple arbitrage positions independently
- Calculates theoretical profit assuming perfect execution
- No exit logic (holds to resolution)

### Data Collection (`lib/polymarket_bot/data_collector.ex`)
- BTC 15-min interval: 30 seconds
- Polymarket API rate limits: ~1000 calls/hour for reads (generous)

---

## Implementation Plan

### Phase 1: Trading Cost Infrastructure

#### 1.1 Create Trading Costs Module

**File**: `lib/polymarket_bot/backtester/trading_costs.ex`

```elixir
defmodule PolymarketBot.Backtester.TradingCosts do
  @moduledoc """
  Models realistic trading costs for backtesting.

  Costs modeled:
  - Slippage: Price impact based on order size and liquidity
  - Fees: Polymarket trading fees (currently 0% maker, ~2% taker on USDC)
  - Spread: Bid-ask spread impact on execution
  """

  @default_config %{
    # Slippage model: linear impact based on position size relative to liquidity
    slippage_factor: 0.001,        # 0.1% base slippage per unit
    slippage_liquidity_scale: true, # Scale slippage by available liquidity

    # Fee structure
    maker_fee: 0.0,               # Polymarket maker fee (currently 0%)
    taker_fee: 0.0,               # Polymarket taker fee (varies, model as 0% for now)

    # Spread simulation
    spread_enabled: true,
    default_spread: 0.01,         # 1 cent default spread if no orderbook data
    spread_from_data: true        # Use actual spread from orderbook snapshots
  }

  def apply_costs(price, side, size, config, market_context)
  def calculate_slippage(price, size, liquidity, config)
  def calculate_fees(notional_value, side, config)
  def apply_spread(price, side, spread, config)
end
```

**Cost Application Logic**:
- **Buy orders**: Pay spread (use ask price) + slippage (price moves up)
- **Sell orders**: Receive spread (use bid price) + slippage (price moves down)
- **Fees**: Applied to notional value of each trade

#### 1.2 Slippage Model

Simple linear slippage model appropriate for prediction markets:

```elixir
# Slippage increases with order size, decreases with liquidity
slippage_pct = base_slippage * (position_size / liquidity_factor)
execution_price = price * (1 + slippage_pct)  # for buys
execution_price = price * (1 - slippage_pct)  # for sells
```

For Gabagool arbitrage (buying both sides):
- Apply slippage to YES price when buying YES
- Apply slippage to NO price when buying NO
- Total slippage impacts guaranteed spread

---

### Phase 2: Multi-Position Support

#### 2.1 Enhanced Equity State

**Current state tuple** (limited to single position):
```elixir
{equity_list, position, entry_price, position_size, capital_at_entry}
```

**New state structure** (supports multiple positions):
```elixir
%{
  equity_curve: [float()],
  cash: float(),                    # Available cash
  positions: [%{
    id: integer(),
    side: :long | :short,
    entry_price: float(),
    size: float(),
    entry_timestamp: DateTime.t(),
    entry_cost: float(),            # Capital allocated
    unrealized_pnl: float()
  }],
  next_position_id: integer(),
  total_realized_pnl: float()
}
```

#### 2.2 Position Management Functions

```elixir
defmodule PolymarketBot.Backtester.PositionManager do
  def open_position(state, side, price, size, timestamp, costs_config)
  def close_position(state, position_id, price, timestamp, costs_config)
  def close_all_positions(state, price, timestamp, costs_config)
  def update_unrealized_pnl(state, current_price)
  def get_total_equity(state)
  def get_open_position_count(state)
end
```

#### 2.3 Signal Enhancement

Extend signal types to support position management:

```elixir
# Current signals
:buy, :sell, :hold, {:buy, size}, {:sell, size}

# Enhanced signals
{:open_long, size}                          # Open new long position
{:open_long, size, position_opts}           # With metadata
{:close_position, position_id}              # Close specific position
{:close_all}                                # Close all positions
{:scale_in, size}                           # Add to existing position
{:scale_out, size}                          # Reduce position size
```

---

### Phase 3: Spread Simulation

#### 3.1 Spread Data Integration

The `orderbook_snapshots` table already captures bid-ask spreads. Enhance data loading to include spread information when available.

**Enhanced price_data map**:
```elixir
%{
  timestamp: DateTime.t(),
  yes_price: float(),
  no_price: float(),
  volume: float(),
  liquidity: float(),
  # New fields
  yes_bid: float() | nil,
  yes_ask: float() | nil,
  no_bid: float() | nil,
  no_ask: float() | nil,
  yes_spread: float() | nil,
  no_spread: float() | nil
}
```

#### 3.2 Spread Application

For Gabagool arbitrage specifically:
- When buying YES: use `yes_ask` (or `yes_price + spread/2` if no orderbook)
- When buying NO: use `no_ask` (or `no_price + spread/2` if no orderbook)
- Effective entry cost = `yes_ask + no_ask` instead of `yes_price + no_price`

This reduces the apparent arbitrage spread by the combined bid-ask spreads.

---

### Phase 4: Strategy Integration

#### 4.1 Update Gabagool Strategy

Modify `gabagool_arb.ex` to account for trading costs in opportunity detection:

```elixir
# Current: raw spread check
spread = 1.0 - (yes_price + no_price)
if spread > config.entry_threshold, do: buy

# Enhanced: net spread after costs
gross_spread = 1.0 - (yes_price + no_price)
estimated_costs = TradingCosts.estimate_round_trip_costs(...)
net_spread = gross_spread - estimated_costs
if net_spread > config.entry_threshold, do: buy
```

#### 4.2 Strategy Configuration Extension

```elixir
@default_config %{
  entry_threshold: 0.02,
  position_size: 1.0,
  max_positions: 5,
  # New cost-aware settings
  cost_aware_entry: true,        # Factor in costs when evaluating opportunities
  min_net_spread: 0.01,          # Minimum spread AFTER costs
  use_limit_orders: false        # If true, assume maker fees (not modeled yet)
}
```

---

### Phase 5: Data Collection Optimization

#### 5.1 Reduce BTC 15-min Interval

**Change**: 30 seconds → 15 seconds

**Rationale**:
- Polymarket API allows ~1000 calls/hour for reads
- Current: 120 calls/hour for BTC 15-min
- New: 240 calls/hour for BTC 15-min
- Still well under rate limit

**File**: `lib/polymarket_bot/data_collector.ex`

```elixir
# Change from:
@btc_15m_interval :timer.seconds(30)

# To:
@btc_15m_interval :timer.seconds(15)
```

#### 5.2 Add Rate Limit Safety

Add defensive rate limiting to handle API throttling gracefully:

```elixir
defp collect_btc_15m(state) do
  # Add jitter to prevent synchronized requests
  jitter = :rand.uniform(1000)
  Process.sleep(jitter)

  # ... existing collection logic ...

  case result do
    {:error, {429, _}} ->
      Logger.warn("Rate limited, backing off")
      schedule_collection(:btc_15m, @btc_15m_interval * 2)
      state
    _ ->
      # normal handling
  end
end
```

---

## File Changes Summary

### New Files
1. `lib/polymarket_bot/backtester/trading_costs.ex` - Cost modeling module
2. `lib/polymarket_bot/backtester/position_manager.ex` - Multi-position tracking

### Modified Files
1. `lib/polymarket_bot/backtester.ex` - Integrate costs and multi-position support
2. `lib/polymarket_bot/backtester/strategies/gabagool_arb.ex` - Cost-aware entry logic
3. `lib/polymarket_bot/data_collector.ex` - 15-second interval for BTC markets

### Test Files (new)
1. `test/polymarket_bot/backtester/trading_costs_test.exs`
2. `test/polymarket_bot/backtester/position_manager_test.exs`

---

## Implementation Order

1. **Trading Costs Module** - Foundation for cost calculations
2. **Position Manager Module** - Multi-position state management
3. **Backtester Integration** - Wire costs and positions into main engine
4. **Gabagool Strategy Update** - Cost-aware opportunity detection
5. **Data Collection Update** - 15-second interval
6. **Tests** - Comprehensive test coverage

---

## Backwards Compatibility

- All cost features are **opt-in** via configuration
- Default behavior (no costs) matches current behavior
- Existing strategy implementations continue to work
- New backtester config options:

```elixir
Backtester.run(
  market_id: "btc-15m-xxx",
  strategy: GabagoolArb,
  # New options (all optional)
  trading_costs: %{
    slippage_factor: 0.001,
    spread_enabled: true
  },
  multi_position: true
)
```

---

## API Rate Limits Reference

From Polymarket documentation:
- Non-trading queries: ~1,000 calls/hour
- Order endpoint: 3,000/10-minute limit
- No authentication required for read operations

Current collection rates:
- Prices: 1/minute = 60/hour
- Order books: 1/5min = 12/hour
- Markets: 1/hour = 1/hour
- BTC 15-min: 2/minute (after change) = 120/hour

**Total after change**: ~193 calls/hour - well under limits

---

## Success Criteria

1. ✅ Slippage simulation reduces reported profits realistically
2. ✅ Transaction costs are configurable and applied consistently
3. ✅ Multiple positions can be opened/tracked simultaneously
4. ✅ Spread simulation uses orderbook data when available
5. ✅ BTC 15-min data collected every 15 seconds
6. ✅ Existing backtests produce identical results with costs disabled
7. ✅ All existing tests pass
