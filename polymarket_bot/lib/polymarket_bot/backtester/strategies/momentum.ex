defmodule PolymarketBot.Backtester.Strategies.Momentum do
  @moduledoc """
  Momentum Strategy for Polymarket prediction markets.

  Strategy logic:
  - Track price momentum over a lookback period
  - Buy when momentum is positive and exceeds threshold (uptrend)
  - Sell when momentum turns negative or falls below exit threshold

  This strategy bets that price trends continue in prediction markets,
  particularly when new information causes sustained price moves.

  Configuration:
  - `lookback` - Periods to calculate momentum (default: 10)
  - `entry_threshold` - Minimum momentum to enter (default: 0.03 = 3%)
  - `exit_threshold` - Momentum level to exit (default: 0.0)
  - `stop_loss` - Maximum allowed loss before exit (default: 0.10 = 10%)
  - `position_size` - Size of each trade (default: 1.0)
  """
  @behaviour PolymarketBot.Backtester.Strategy

  @default_config %{
    lookback: 10,
    entry_threshold: 0.03,
    exit_threshold: 0.0,
    stop_loss: 0.10,
    position_size: 1.0
  }

  @impl true
  def name, do: "Momentum"

  @impl true
  def default_config, do: @default_config

  @impl true
  def init(config) do
    config = Map.merge(@default_config, config || %{})

    state = %{
      config: config,
      price_history: [],
      position: nil,
      entry_price: nil,
      highest_since_entry: nil,
      trades: []
    }

    {:ok, state}
  end

  @impl true
  def on_price(price_data, state) do
    %{yes_price: price} = price_data
    %{config: config, price_history: history, position: position} = state

    # Add price to history
    history = [price | history] |> Enum.take(config.lookback + 1)
    state = %{state | price_history: history}

    # Need enough data for momentum calculation
    if length(history) <= config.lookback do
      {:hold, state}
    else
      # Calculate momentum as percentage change over lookback period
      old_price = List.last(history)
      momentum = if old_price > 0, do: (price - old_price) / old_price, else: 0.0

      cond do
        # No position: look for entry on strong positive momentum
        is_nil(position) and momentum > config.entry_threshold ->
          state = %{
            state
            | position: :long,
              entry_price: price,
              highest_since_entry: price
          }

          {{:buy, config.position_size}, state}

        # Have position: check exit conditions
        position == :long ->
          highest = max(state.highest_since_entry || price, price)
          state = %{state | highest_since_entry: highest}

          current_return = (price - state.entry_price) / state.entry_price

          should_exit =
            momentum < config.exit_threshold or
              current_return < -config.stop_loss

          if should_exit do
            trade = %{
              entry_price: state.entry_price,
              exit_price: price,
              return: current_return,
              highest_price: highest,
              exit_reason:
                if(current_return < -config.stop_loss, do: :stop_loss, else: :momentum),
              timestamp: price_data.timestamp
            }

            state = %{
              state
              | position: nil,
                entry_price: nil,
                highest_since_entry: nil,
                trades: [trade | state.trades]
            }

            {{:sell, config.position_size}, state}
          else
            {:hold, state}
          end

        # Hold
        true ->
          {:hold, state}
      end
    end
  end

  @impl true
  def on_complete(state) do
    stats = %{
      total_trades: length(state.trades),
      trades: Enum.reverse(state.trades),
      final_position: state.position,
      stop_loss_exits: Enum.count(state.trades, &(&1.exit_reason == :stop_loss))
    }

    {:ok, stats}
  end
end
