defmodule PolymarketBot.Backtester.Strategies.MeanReversion do
  @moduledoc """
  Mean Reversion Strategy for Polymarket prediction markets.

  Strategy logic:
  - Track the moving average of YES prices
  - Buy when price is significantly below the moving average (oversold)
  - Sell when price returns to or exceeds the moving average (mean reversion)

  This works well for prediction markets where prices tend to oscillate
  around fair value as new information comes in.

  Configuration:
  - `window_size` - Number of periods for moving average (default: 20)
  - `threshold` - Deviation threshold to trigger signals (default: 0.05 = 5%)
  - `position_size` - Size of each trade (default: 1.0)
  """
  @behaviour PolymarketBot.Backtester.Strategy

  @default_config %{
    window_size: 20,
    threshold: 0.05,
    position_size: 1.0
  }

  @impl true
  def name, do: "Mean Reversion"

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
      trades: []
    }

    {:ok, state}
  end

  @impl true
  def on_price(price_data, state) do
    %{yes_price: price} = price_data
    %{config: config, price_history: history, position: position} = state

    # Add price to history
    history = [price | history] |> Enum.take(config.window_size)
    state = %{state | price_history: history}

    # Need enough data for moving average
    if length(history) < config.window_size do
      {:hold, state}
    else
      moving_avg = Enum.sum(history) / length(history)
      deviation = (price - moving_avg) / moving_avg

      cond do
        # No position: look for entry (price below MA by threshold)
        is_nil(position) and deviation < -config.threshold ->
          state = %{state | position: :long, entry_price: price}
          {{:buy, config.position_size}, state}

        # Have position: look for exit (price returned to or above MA)
        position == :long and deviation >= 0 ->
          trade = %{
            entry_price: state.entry_price,
            exit_price: price,
            return: (price - state.entry_price) / state.entry_price,
            timestamp: price_data.timestamp
          }

          state = %{
            state
            | position: nil,
              entry_price: nil,
              trades: [trade | state.trades]
          }

          {{:sell, config.position_size}, state}

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
      final_position: state.position
    }

    {:ok, stats}
  end
end
