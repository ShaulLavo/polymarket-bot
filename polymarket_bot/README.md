# Polymarket Trading Bot

An Elixir-based trading bot for Polymarket prediction markets.

## Features

- **Real-time Data Fetching** - Fetch events, markets, order books, and price history from Polymarket APIs
- **Data Persistence** - SQLite database stores all price and order book snapshots forever
- **Arbitrage Scanner** - Scans for Gabagool arbitrage opportunities (YES + NO < $1.00)
- **REST API** - HTTP endpoints for accessing data and bot status

## Quick Start

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Run the server
mix run --no-halt

# Or run in interactive mode
iex -S mix
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

## Data Collection

The `DataCollector` GenServer automatically collects and persists:

- **Price Snapshots** - Every 1 minute
- **Order Book Snapshots** - Every 5 minutes
- **Market Metadata** - Every hour

Data is stored in SQLite at `priv/polymarket_data.db`.

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
│   ├── data_collector.ex       # Data collection GenServer
│   ├── repo.ex                 # Ecto Repo
│   ├── router.ex               # HTTP router (Plug)
│   └── schema/
│       ├── market.ex           # Market schema
│       ├── orderbook_snapshot.ex
│       └── price_snapshot.ex
```

## Dependencies

- `plug_cowboy` - HTTP server
- `jason` - JSON encoding/decoding
- `req` - HTTP client
- `signet` - Ethereum/EIP-712 signing
- `ecto_sql` + `ecto_sqlite3` - Database ORM

## Research & Documentation

See `/home/shaul/ellie/memory/` for research documents:
- `research-polymarket-deep-dive.md` - Ecosystem research
- `research-polymarket-data-access.md` - API documentation

## Trading Strategies (Research)

1. **Gabagool Arbitrage** - Buy YES + NO when combined price < $1.00
2. **Panic Catcher** - Place limit orders to catch panic sellers
3. **Copy Trading** - Mirror successful wallets

## License

Private - Internal use only
