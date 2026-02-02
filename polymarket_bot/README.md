# Polymarket Trading Bot

An Elixir-based trading bot for Polymarket prediction markets with live data collection, backtesting, and a hacker-aesthetic LiveView dashboard.

## Features

- **24/7 Data Collection** - 10-second intervals for BTC 15-min markets (~28,000+ snapshots)
- **Data Persistence** - SQLite database stores all price and order book snapshots forever
- **Technical Analysis** - VWAP, RSI, MACD, Heiken Ashi indicators with regime detection
- **Backtesting Engine** - Test strategies with trading costs, slippage, and multi-position support
- **LiveView Dashboard** - Real-time terminal-style UI with ASCII charts and position tracking
- **REST API** - HTTP endpoints for accessing data and bot status

## Quick Start

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Start the Phoenix server (includes LiveView dashboard)
mix phx.server

# Visit the dashboard at http://localhost:4000
# - Dashboard: Real-time BTC prices + ASCII spread chart
# - Positions: Portfolio tracking + P&L
# - Backtest: Strategy selector + equity curves

# Or run in interactive mode
iex -S mix phx.server
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check |
| `GET /events?limit=N` | Fetch active events |
| `GET /markets?limit=N` | Fetch active markets with prices |
| `GET /book/:token_id` | Get order book for a token |
| `GET /history/:token_id` | Get historical prices |
| `GET /arbitrage` | Scan for arbitrage opportunities |
| `GET /balance` | Get wallet balance (placeholder) |

## LiveView Dashboard

**Terminal/Hacker Aesthetic** - Dark background, green/amber text, monospace fonts, ASCII art

Navigate to `http://localhost:4000` for:

- **Dashboard (`/`)** - Real-time BTC 15-min prices, ASCII spread chart, arb scanner
- **Positions (`/positions`)** - Portfolio statistics, P&L tracking, open positions
- **Backtest (`/backtest`)** - Strategy selector, equity curves, performance metrics

Updates in real-time via Phoenix PubSub.

## Data Collection

The `DataCollector` GenServer automatically collects and persists:

- **BTC 15-min Markets** - Every 10 seconds (~8,640 snapshots/day)
- **Price Snapshots** - Every 1 minute for general markets
- **Order Book Snapshots** - Every 5 minutes
- **Market Metadata** - Every hour

Data is stored in SQLite at `priv/polymarket_data.db` (currently **28,000+ snapshots**).

## Testing

```bash
# Run all tests
mix test

# Run only unit tests (exclude external API calls)
mix test --exclude external

# Run with coverage
mix test --cover
```

## Architecture

```
lib/
├── polymarket_bot.ex           # Main module
├── polymarket_bot/
│   ├── api.ex                  # Polymarket API client
│   ├── application.ex          # OTP Application
│   ├── data_collector.ex       # 24/7 data collection GenServer
│   ├── repo.ex                 # Ecto Repo
│   ├── router.ex               # HTTP router (Plug)
│   ├── backtester/
│   │   ├── backtester.ex       # Backtesting engine
│   │   ├── trading_costs.ex    # Slippage, fees, spread simulation
│   │   ├── position_manager.ex # Multi-position tracking
│   │   └── strategies/
│   │       ├── gabagool_arb.ex     # Gabagool arbitrage
│   │       └── ta_signals.ex       # TA-based strategy
│   ├── indicators/
│   │   ├── vwap.ex             # Volume Weighted Average Price
│   │   ├── rsi.ex              # Relative Strength Index
│   │   ├── macd.ex             # Moving Average Convergence/Divergence
│   │   └── heiken_ashi.ex      # Heiken Ashi candlesticks
│   ├── engines/
│   │   ├── edge.ex             # Edge calculator
│   │   ├── probability.ex      # Probability estimator
│   │   └── regime.ex           # Market regime detector
│   ├── data/
│   │   ├── binance.ex          # Binance real-time API
│   │   ├── binance_historical.ex # Historical candles
│   │   └── chainlink_ws.ex     # Chainlink live data WebSocket
│   ├── utils/
│   │   └── timing.ex           # 15-min window utilities
│   ├── history_fetcher.ex      # Historical data fetcher
│   ├── schema/
│   │   ├── market.ex           # Market schema
│   │   ├── orderbook_snapshot.ex
│   │   └── price_snapshot.ex
│   └── web/
│       ├── endpoint.ex         # Phoenix endpoint
│       ├── live/
│       │   ├── dashboard_live.ex   # Main dashboard
│       │   ├── positions_live.ex   # Portfolio tracker
│       │   └── backtest_live.ex    # Backtest UI
│       └── components/
│           └── core_components.ex
```

## Dependencies

- `plug_cowboy` - HTTP server
- `jason` - JSON encoding/decoding
- `req` - HTTP client
- `signet` - Ethereum/EIP-712 signing
- `ecto_sql` + `ecto_sqlite3` - Database ORM

## Research & Documentation

See `/home/shaul/ellie/memory/` for research documents:
- `research-polymarket-deep-dive.md` - Ecosystem research (32KB)
- `research-polymarket-data-access.md` - API documentation
- `research-polymarket-arbitrage.md` - Arbitrage strategies (34KB)
- `research-polymarket-backtesting.md` - Backtesting methodology (29KB)
- `polymarket-next-steps.md` - Strategy selection guide
- `nightly-build-YYYY-MM-DD.md` - Daily autonomous work summaries

## Trading Strategies

### Implemented

1. **Gabagool Arbitrage** - Asymmetric accumulation when avg(YES) + avg(NO) < $1.00
   - **Key insight**: NOT instant arb - accumulate cheap shares over time through oscillations
   - Target: BTC 15-min markets with high volatility
   - Real example: 1266 YES @ $0.517 + 1295 NO @ $0.449 = $0.966 cost for $1.00 payout

2. **TA Signals Strategy** - Technical analysis-based trading
   - VWAP, RSI, MACD, Heiken Ashi indicators
   - Regime detection (trend_up/down/range/chop)
   - Edge calculation (modelProbability - marketPrice)
   - Time-aware thresholds (EARLY/MID/LATE phases)

### In Research

3. **Panic Catcher** - Place limit orders to catch panic sellers
4. **Copy Trading** - Mirror successful wallets
5. **Corrective AI** - Regime-aware bet sizing with conditional position scaling

## License

Private - Internal use only
