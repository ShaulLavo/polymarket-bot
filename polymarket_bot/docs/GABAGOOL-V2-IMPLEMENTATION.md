# Gabagool V2 - Asymmetric Accumulation Strategy

*Implementation guide for the CORRECT Gabagool approach*

---

## 🎯 Key Insight: NOT Instant Arb!

**Wrong understanding:** Buy YES + NO simultaneously when spread exists → instant profit

**Correct understanding:** Buy YES when it dips, buy NO when IT dips (DIFFERENT times) → accumulate profit over multiple price oscillations

---

## 📊 How It Actually Works

### The Setup
Focus on **15-minute BTC markets** specifically:
- High volatility = emotional trading
- Predictable oscillations as sentiment shifts
- Each 15-min window is a new market

### The Mechanism

```
Time T1: BTC pumps → traders panic buy YES → YES expensive, NO cheap
         → Buy NO @ $0.45

Time T2: BTC dumps → traders panic buy NO → NO expensive, YES cheap
         → Buy YES @ $0.52

Result: 1 YES ($0.52) + 1 NO ($0.45) = $0.97 cost for $1.00 guaranteed
```

### Real Example (from gabagool's trades)

| Side | Quantity | Avg Price | Total Cost |
|------|----------|-----------|------------|
| YES  | 1,266    | $0.517    | $654.52    |
| NO   | 1,295    | $0.449    | $581.46    |
| **Total** | 1,266* | $0.966** | **$1,235.98** |

*Profit locked on min(YES, NO) = 1,266 shares
**Combined cost per locked share

**Guaranteed payout:** 1,266 × $1.00 = $1,266.00
**Profit:** $30.02 (2.4% return per 15-min window)

---

## 🏗️ Implementation Architecture

### Core Data Structures

```elixir
defmodule PolymarketBot.Strategies.GabagoolV2 do
  @moduledoc """
  Asymmetric accumulation strategy for binary markets.
  
  Key principle: Buy each side when it dips, not simultaneously.
  Profit when avg_yes + avg_no < 1.00 and quantities balanced.
  """
  
  defstruct [
    :market_id,
    :window_epoch,
    # YES position
    :yes_quantity,
    :yes_total_cost,
    :yes_avg_price,
    :yes_last_buy_price,
    :yes_last_buy_time,
    # NO position  
    :no_quantity,
    :no_total_cost,
    :no_avg_price,
    :no_last_buy_price,
    :no_last_buy_time,
    # Thresholds
    :buy_threshold,      # Buy when price < running_avg * threshold
    :target_combined,    # Stop when combined_avg < target
    :max_position_size,  # Max shares per side
    # State
    :status,             # :accumulating | :locked | :resolved
    :locked_profit
  ]
end
```

### Position State

```elixir
defmodule PolymarketBot.Strategies.GabagoolV2.Position do
  @doc """
  Tracks running average cost and quantity for one side.
  """
  
  def add_shares(position, quantity, price) do
    new_total_cost = position.total_cost + (quantity * price)
    new_quantity = position.quantity + quantity
    new_avg_price = new_total_cost / new_quantity
    
    %{position |
      quantity: new_quantity,
      total_cost: new_total_cost,
      avg_price: new_avg_price,
      last_buy_price: price,
      last_buy_time: DateTime.utc_now()
    }
  end
  
  def combined_cost(yes_position, no_position) do
    yes_position.avg_price + no_position.avg_price
  end
  
  def locked_shares(yes_position, no_position) do
    min(yes_position.quantity, no_position.quantity)
  end
  
  def profit_if_resolved(yes_position, no_position) do
    locked = locked_shares(yes_position, no_position)
    cost = (yes_position.avg_price + no_position.avg_price) * locked
    payout = locked * 1.0
    payout - cost
  end
end
```

### Buy Signal Detection

```elixir
defmodule PolymarketBot.Strategies.GabagoolV2.Signals do
  @doc """
  Detect when to buy YES or NO based on price oscillations.
  """
  
  @buy_threshold 0.95  # Buy when price < 95% of running average
  @min_wait_ms 5_000   # Minimum 5 seconds between buys on same side
  
  def should_buy_yes?(state, current_yes_price) do
    cond do
      # Don't buy if we already have enough locked profit
      combined_avg(state) < state.target_combined -> false
      
      # Don't buy if we bought YES recently
      recently_bought_yes?(state) -> false
      
      # Don't buy if position maxed out
      state.yes_quantity >= state.max_position_size -> false
      
      # BUY if price dipped below threshold of our running average
      state.yes_quantity == 0 ->
        current_yes_price < 0.55  # Initial entry below 55%
        
      current_yes_price < state.yes_avg_price * @buy_threshold ->
        true
        
      true -> false
    end
  end
  
  def should_buy_no?(state, current_no_price) do
    cond do
      combined_avg(state) < state.target_combined -> false
      recently_bought_no?(state) -> false
      state.no_quantity >= state.max_position_size -> false
      
      state.no_quantity == 0 ->
        current_no_price < 0.55
        
      current_no_price < state.no_avg_price * @buy_threshold ->
        true
        
      true -> false
    end
  end
  
  defp combined_avg(state) do
    if state.yes_quantity > 0 and state.no_quantity > 0 do
      state.yes_avg_price + state.no_avg_price
    else
      1.0  # No position yet
    end
  end
  
  defp recently_bought_yes?(state) do
    case state.yes_last_buy_time do
      nil -> false
      time -> DateTime.diff(DateTime.utc_now(), time, :millisecond) < @min_wait_ms
    end
  end
end
```

### Order Sizing

```elixir
defmodule PolymarketBot.Strategies.GabagoolV2.Sizing do
  @doc """
  Determine how many shares to buy.
  
  Key: Keep YES and NO quantities roughly balanced.
  """
  
  @max_imbalance 1.2  # Max ratio between YES and NO quantities
  @base_order_size 100  # Base order in shares
  
  def calculate_order_size(state, side) do
    case side do
      :yes -> calculate_yes_size(state)
      :no -> calculate_no_size(state)
    end
  end
  
  defp calculate_yes_size(state) do
    cond do
      # First order - use base size
      state.yes_quantity == 0 -> @base_order_size
      
      # If YES is lagging NO, buy more to catch up
      state.yes_quantity < state.no_quantity / @max_imbalance ->
        catch_up_size(state.no_quantity, state.yes_quantity)
      
      # Normal order
      true -> @base_order_size
    end
    |> min(state.max_position_size - state.yes_quantity)
    |> max(0)
  end
  
  defp catch_up_size(leading, lagging) do
    target = leading / @max_imbalance
    needed = target - lagging
    min(needed, @base_order_size * 2)  # Don't catch up too aggressively
  end
end
```

---

## 📈 Backtest Implementation

### Test File: `test/polymarket_bot/strategies/gabagool_v2_test.exs`

```elixir
defmodule PolymarketBot.Strategies.GabagoolV2Test do
  use ExUnit.Case, async: true
  
  alias PolymarketBot.Strategies.GabagoolV2
  
  describe "asymmetric accumulation" do
    test "accumulates profit through price oscillations" do
      # Simulate price oscillation
      prices = [
        # YES dips first
        {0.52, 0.50},  # Buy NO @ 0.50
        {0.51, 0.51},  # Wait
        {0.48, 0.54},  # Buy YES @ 0.48, NO expensive
        {0.55, 0.47},  # Buy NO @ 0.47, YES expensive
        {0.46, 0.56},  # Buy YES @ 0.46
        # Resolution
      ]
      
      state = GabagoolV2.new(target_combined: 0.97)
      
      final_state = Enum.reduce(prices, state, fn {yes_price, no_price}, acc ->
        GabagoolV2.process_tick(acc, yes_price, no_price)
      end)
      
      # Combined avg should be below target
      combined = final_state.yes_avg_price + final_state.no_avg_price
      assert combined < 0.97
      
      # Should have profit locked
      assert final_state.locked_profit > 0
    end
    
    test "doesn't buy when combined avg already meets target" do
      state = %GabagoolV2{
        yes_quantity: 100, yes_avg_price: 0.47,
        no_quantity: 100, no_avg_price: 0.48,
        target_combined: 0.97
      }
      
      # Combined = 0.95, already < 0.97 target
      # Should NOT buy more even if price dips
      assert GabagoolV2.Signals.should_buy_yes?(state, 0.40) == false
      assert GabagoolV2.Signals.should_buy_no?(state, 0.40) == false
    end
    
    test "maintains balanced positions" do
      state = %GabagoolV2{
        yes_quantity: 200, yes_avg_price: 0.50,
        no_quantity: 100, no_avg_price: 0.50,
        max_position_size: 1000
      }
      
      # YES is 2x NO, should prioritize buying NO
      yes_size = GabagoolV2.Sizing.calculate_order_size(state, :yes)
      no_size = GabagoolV2.Sizing.calculate_order_size(state, :no)
      
      assert no_size > yes_size  # Should buy more NO to balance
    end
  end
  
  describe "profit calculation" do
    test "calculates locked profit correctly" do
      state = %GabagoolV2{
        yes_quantity: 1266, yes_avg_price: 0.517,
        no_quantity: 1295, no_avg_price: 0.449
      }
      
      locked = GabagoolV2.Position.locked_shares(state.yes, state.no)
      profit = GabagoolV2.Position.profit_if_resolved(state.yes, state.no)
      
      assert locked == 1266
      # Cost: 1266 * (0.517 + 0.449) = $1,222.92
      # Payout: 1266 * 1.00 = $1,266.00
      # Profit: $43.08
      assert_in_delta profit, 43.08, 1.0
    end
  end
end
```

---

## 🔄 Integration with Data Collector

### Price Stream Handler

```elixir
defmodule PolymarketBot.Strategies.GabagoolV2.Handler do
  use GenServer
  
  alias PolymarketBot.Strategies.GabagoolV2
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Subscribe to BTC 15-min market updates
    Phoenix.PubSub.subscribe(PolymarketBot.PubSub, "btc_15m_prices")
    
    state = %{
      active_positions: %{},  # market_id => GabagoolV2 state
      config: opts[:config] || default_config()
    }
    
    {:ok, state}
  end
  
  def handle_info({:price_update, market_id, yes_price, no_price}, state) do
    position = Map.get(state.active_positions, market_id)
                |> process_or_create(market_id, state.config)
    
    new_position = GabagoolV2.process_tick(position, yes_price, no_price)
    
    # Execute trades if needed
    new_position = maybe_execute_trades(new_position, yes_price, no_price)
    
    new_state = put_in(state.active_positions[market_id], new_position)
    {:noreply, new_state}
  end
  
  defp maybe_execute_trades(position, yes_price, no_price) do
    cond do
      GabagoolV2.Signals.should_buy_yes?(position, yes_price) ->
        size = GabagoolV2.Sizing.calculate_order_size(position, :yes)
        execute_buy(position.market_id, :yes, size, yes_price)
        GabagoolV2.Position.add_shares(position, :yes, size, yes_price)
        
      GabagoolV2.Signals.should_buy_no?(position, no_price) ->
        size = GabagoolV2.Sizing.calculate_order_size(position, :no)
        execute_buy(position.market_id, :no, size, no_price)
        GabagoolV2.Position.add_shares(position, :no, size, no_price)
        
      true ->
        position
    end
  end
end
```

---

## 📊 Dashboard Integration

### LiveView Component

```elixir
defmodule PolymarketBotWeb.Live.GabagoolDashboard do
  use PolymarketBotWeb, :live_view
  
  def render(assigns) do
    ~H"""
    <div class="gabagool-dashboard terminal-style">
      <h2>⚡ GABAGOOL V2 - Asymmetric Accumulation</h2>
      
      <div class="positions">
        <%= for {market_id, pos} <- @positions do %>
          <div class="position-card">
            <h3><%= market_id %></h3>
            
            <div class="sides">
              <div class="yes-side">
                <span class="label">YES</span>
                <span class="qty"><%= pos.yes_quantity %></span>
                <span class="avg">@ $<%= Float.round(pos.yes_avg_price, 3) %></span>
              </div>
              
              <div class="no-side">
                <span class="label">NO</span>
                <span class="qty"><%= pos.no_quantity %></span>
                <span class="avg">@ $<%= Float.round(pos.no_avg_price, 3) %></span>
              </div>
            </div>
            
            <div class="combined">
              Combined: $<%= Float.round(pos.yes_avg_price + pos.no_avg_price, 3) %>
              <%= if pos.yes_avg_price + pos.no_avg_price < 1.0 do %>
                <span class="profit">✓ PROFITABLE</span>
              <% end %>
            </div>
            
            <div class="locked">
              Locked: <%= min(pos.yes_quantity, pos.no_quantity) %> shares
              Profit: $<%= Float.round(pos.locked_profit, 2) %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
```

---

## ✅ Implementation Checklist

### Phase 1: Core Logic
- [ ] Create `lib/polymarket_bot/strategies/gabagool_v2.ex`
- [ ] Create `lib/polymarket_bot/strategies/gabagool_v2/position.ex`
- [ ] Create `lib/polymarket_bot/strategies/gabagool_v2/signals.ex`
- [ ] Create `lib/polymarket_bot/strategies/gabagool_v2/sizing.ex`
- [ ] Write tests for each module

### Phase 2: Integration
- [ ] Create GenServer handler for price stream
- [ ] Integrate with existing PubSub
- [ ] Add to backtest strategies
- [ ] Validate against historical data

### Phase 3: Trading
- [ ] Connect to CLOB API for order execution
- [ ] Add paper trading mode
- [ ] Implement risk controls (max loss, position limits)
- [ ] Add monitoring/alerts

### Phase 4: Dashboard
- [ ] Add LiveView component
- [ ] Real-time position tracking
- [ ] Historical P&L chart
- [ ] Trade log

---

## 🎓 Key Lessons

1. **Price oscillations are predictable** - 15-min BTC markets swing with sentiment
2. **Patience beats speed** - Accumulate over time, don't rush
3. **Balance matters** - Keep YES ≈ NO quantities for maximum locked profit
4. **Stop when profitable** - Once combined_avg < target, stop buying
5. **Small edges compound** - 2-3% per window × many windows = real money

---

*Created: 2026-02-02 23:00 (Nightly Autonomous Work)*
*Ready for Claude Code implementation*
