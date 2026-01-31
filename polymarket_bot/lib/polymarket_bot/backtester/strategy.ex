defmodule PolymarketBot.Backtester.Strategy do
  @moduledoc """
  Behaviour for backtesting strategies.

  Implement this behaviour to create a new trading strategy.
  The backtester will call these functions in sequence:

  1. `init/1` - Initialize strategy state with config
  2. `on_price/2` - Called for each price snapshot, returns signals
  3. `on_complete/1` - Called when backtest completes, for cleanup/final state
  """

  @type signal :: :buy | :sell | :hold | {:buy, float()} | {:sell, float()}
  @type state :: map()
  @type config :: map()
  @type price_data :: %{
          timestamp: DateTime.t(),
          yes_price: float(),
          no_price: float(),
          volume: float() | nil,
          liquidity: float() | nil
        }

  @doc """
  Initialize the strategy with configuration.
  Returns initial state.
  """
  @callback init(config()) :: {:ok, state()} | {:error, term()}

  @doc """
  Process a price snapshot and return a trading signal.

  Returns:
  - `:hold` - No action
  - `:buy` - Buy at current price
  - `:sell` - Sell current position
  - `{:buy, amount}` - Buy specific amount
  - `{:sell, amount}` - Sell specific amount
  """
  @callback on_price(price_data(), state()) :: {signal(), state()}

  @doc """
  Called when backtest is complete. 
  Use for final calculations or cleanup.
  """
  @callback on_complete(state()) :: {:ok, map()} | {:error, term()}

  @doc """
  Returns the strategy name for reporting.
  """
  @callback name() :: String.t()

  @doc """
  Returns default configuration for this strategy.
  """
  @callback default_config() :: config()

  @optional_callbacks [on_complete: 1, default_config: 0]
end
