# Current Development Plan

*Last updated: 2026-02-02*

---

## ✅ Completed (Jan 27 - Feb 1)

### Phase 1: Backtesting Infrastructure ✅
- **PR #2 (MERGED)** - Backtester Enhancements (+3,936 lines)
  - Trading costs module (slippage, fees, spread)
  - Position manager (multi-position support)
  - Cost-aware Gabagool strategy
  - 117 tests passing

### Phase 2: LiveView Dashboard ✅
- **PR #3 (MERGED)** - LiveView Dashboard (+11,965 lines)
  - Terminal/hacker aesthetic (dark bg, green/amber text, ASCII art)
  - Real-time BTC price tracking with ASCII charts
  - Arb scanner, positions tracker, backtest UI
  - Phoenix PubSub for live updates

### Phase 3: TA Signals Infrastructure ✅
- **PR #5 (READY TO MERGE)** - TA Signals (+4,631 lines)
  - 4 Indicators: VWAP, RSI, MACD, Heiken Ashi
  - 3 Engines: Edge, Probability, Regime
  - 3 Data Sources: Binance, Binance Historical, Chainlink WS
  - Timing utilities, History fetcher
  - TASignals backtest strategy
  - 245 tests passing

### Phase 4: Data Collection ✅
- **PR #4 (MERGED)** - 10-second collection intervals
  - 24/7 data collector running in tmux
  - ~28,000+ snapshots collected
  - SQLite storage at `priv/polymarket_data.db`

---

## 🟡 In Progress

### Gabagool Strategy Rewrite
**Status:** Needs implementation

**Key insight discovered:** Gabagool is NOT instant arb - it's ASYMMETRIC accumulation over time!

**How it actually works:**
1. Watch 15-minute BTC markets specifically
2. Buy YES when it dips cheap
3. Buy NO when IT dips cheap (different time, not simultaneous)
4. Keep running averages: `avg_YES + avg_NO < $1.00`
5. When quantities balanced = guaranteed profit at resolution

**Example from real trades:**
- YES: 1,266 shares @ avg $0.517
- NO: 1,295 shares @ avg $0.449
- Combined cost: $0.966 for $1.00 payout
- Profit: ~$60 per 15-min window

**Implementation needs:**
- Track running average cost per share (not spot price)
- Track separate YES/NO quantities
- Identify entry points based on oscillations
- Profit realized when `min(Qty_YES, Qty_NO) > (Cost_YES + Cost_NO)`

**Files to modify:**
- `lib/polymarket_bot/backtester/strategies/gabagool_arb.ex`
- Add tests for asymmetric accumulation

---

## 🔵 Next Up

### 1. Strategy Selection & Testing
Pick ONE strategy to implement first for live trading:

**Option A: TA Signals** (ready after PR #5 merge)
- Pros: Infrastructure complete, regime detection ready
- Cons: Needs tuning on real data, more complex

**Option B: Corrected Gabagool** (needs rewrite)
- Pros: Proven concept ($40M extracted by others)
- Cons: Requires precise timing and oscillation detection

**Option C: Panic Catcher** (not implemented)
- Pros: Simple, low frequency
- Cons: Needs orderbook depth monitoring

**Recommendation:** Test TA Signals first (already built), then implement corrected Gabagool.

### 2. Historical Data Collection
**Goal:** Calibrate regimes and backtest strategies accurately

**Tasks:**
- Use `HistoryFetcher.collect_btc_15m_history(hours: 168)` for past week
- Fetch Binance 1m/5m candles for finer granularity
- Store in same format as real-time snapshots
- Run backtests on historical data to validate strategies

### 3. Live Trading Infrastructure
**Once strategy is selected and tested:**

**Tasks:**
- Wallet integration (EIP-712 signing with Signet)
- Order placement via CLOB API
- Position tracking (sync with chain state)
- Risk management (max position size, stop loss)
- Monitoring & alerts (Discord/Telegram notifications)

**Files to create:**
- `lib/polymarket_bot/trader.ex` - Trading execution
- `lib/polymarket_bot/wallet.ex` - Wallet management
- `lib/polymarket_bot/risk_manager.ex` - Risk controls

### 4. Dashboard Enhancements
**Optional improvements:**

- WebSocket live updates (replace PubSub polling)
- Trade execution UI
- Historical performance charts
- Strategy comparison view
- Mobile responsive layout

---

## 📊 Progress Tracker

| Phase | Status | Lines | Tests |
|-------|--------|-------|-------|
| Backtesting | ✅ MERGED | +3,936 | 117 |
| LiveView Dashboard | ✅ MERGED | +11,965 | 12 |
| Data Collection | ✅ MERGED | +50 | - |
| TA Signals | ⏳ PR #5 | +4,631 | 245 |
| Gabagool Rewrite | 🔴 TODO | - | - |
| Historical Data | 🔵 NEXT | - | - |
| Live Trading | 🔵 PLANNED | - | - |

**Total shipped so far:** ~20,500 lines in 5 days (Jan 27 - Feb 1) 🔥

---

## 🎯 Success Metrics

### Backtesting (ACHIEVED ✅)
- [x] Slippage simulation reduces reported profits realistically
- [x] Transaction costs configurable and applied consistently
- [x] Multiple positions tracked simultaneously
- [x] Spread simulation uses orderbook data
- [x] All existing tests pass

### Trading (PENDING)
- [ ] Strategy tested on 1+ week of historical data
- [ ] Backtested Sharpe ratio > 1.5
- [ ] Max drawdown < 20%
- [ ] Live trading executes without errors
- [ ] Risk controls prevent catastrophic loss

---

## 📝 Notes

**Development Speed:** Averaging ~4,100 lines/day with Claude Code assistance

**Key Learnings:**
- `ai --continue` recovers crashed sessions
- Elixir pattern matching excellent for strategy logic
- Phoenix LiveView perfect for real-time dashboards
- SQLite handles high-frequency writes well

**Tech Stack:**
- Elixir 1.19.5 + OTP 28.3.1
- Phoenix 1.8 + LiveView
- Ecto + SQLite3
- TailwindCSS

---

*See IMPLEMENTATION-HISTORY.md for original backtester enhancement plan.*
