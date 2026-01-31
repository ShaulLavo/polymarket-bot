defmodule PolymarketBot.Backtester.StrategiesTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Backtester.Strategies.{MeanReversion, Momentum}

  describe "MeanReversion" do
    test "initializes with default config" do
      {:ok, state} = MeanReversion.init(%{})

      assert state.config.window_size == 20
      assert state.config.threshold == 0.05
      assert state.position == nil
    end

    test "holds when insufficient data" do
      {:ok, state} = MeanReversion.init(%{window_size: 5})

      price_data = %{
        yes_price: 0.50,
        no_price: 0.50,
        volume: 1000.0,
        liquidity: 5000.0,
        timestamp: DateTime.utc_now()
      }

      {signal, _state} = MeanReversion.on_price(price_data, state)
      assert signal == :hold
    end

    test "buys when price drops below moving average threshold" do
      config = %{window_size: 5, threshold: 0.05, position_size: 1.0}
      {:ok, state} = MeanReversion.init(config)

      # Build up price history at 0.50
      state =
        Enum.reduce(1..5, state, fn _, acc ->
          price_data = make_price_data(0.50)
          {_signal, new_state} = MeanReversion.on_price(price_data, acc)
          new_state
        end)

      # Price drops 10% below average - should trigger buy
      price_data = make_price_data(0.45)
      {signal, new_state} = MeanReversion.on_price(price_data, state)

      assert signal == {:buy, 1.0}
      assert new_state.position == :long
      assert new_state.entry_price == 0.45
    end

    test "sells when price returns to moving average" do
      config = %{window_size: 5, threshold: 0.05, position_size: 1.0}
      {:ok, state} = MeanReversion.init(config)

      # Build history and enter position
      state =
        Enum.reduce(1..5, state, fn _, acc ->
          {_signal, new_state} = MeanReversion.on_price(make_price_data(0.50), acc)
          new_state
        end)

      {_signal, state} = MeanReversion.on_price(make_price_data(0.45), state)

      # Price returns to MA
      {signal, new_state} = MeanReversion.on_price(make_price_data(0.50), state)

      assert signal == {:sell, 1.0}
      assert new_state.position == nil
      assert length(new_state.trades) == 1
    end

    test "on_complete returns trade stats" do
      {:ok, state} = MeanReversion.init(%{})

      state = %{state | trades: [%{return: 0.10}, %{return: -0.05}]}

      {:ok, stats} = MeanReversion.on_complete(state)

      assert stats.total_trades == 2
    end
  end

  describe "Momentum" do
    test "initializes with default config" do
      {:ok, state} = Momentum.init(%{})

      assert state.config.lookback == 10
      assert state.config.entry_threshold == 0.03
      assert state.position == nil
    end

    test "buys on strong upward momentum" do
      config = %{lookback: 3, entry_threshold: 0.05, position_size: 1.0}
      {:ok, state} = Momentum.init(config)

      # Build history with prices going from 0.45 to 0.50
      prices = [0.45, 0.46, 0.47, 0.50]

      {final_signal, final_state} =
        Enum.reduce(prices, {:hold, state}, fn price, {_signal, acc_state} ->
          Momentum.on_price(make_price_data(price), acc_state)
        end)

      # 0.50 is 11% above 0.45 - should trigger buy
      assert final_signal == {:buy, 1.0}
      assert final_state.position == :long
    end

    test "exits on stop loss" do
      config = %{lookback: 3, entry_threshold: 0.03, stop_loss: 0.05, position_size: 1.0}
      {:ok, state} = Momentum.init(config)

      # Enter a position
      state = %{
        state
        | position: :long,
          entry_price: 0.50,
          highest_since_entry: 0.50,
          price_history: [0.50, 0.48, 0.46, 0.45]
      }

      # Price drops 12% - should trigger stop loss
      price_data = make_price_data(0.44)
      {signal, new_state} = Momentum.on_price(price_data, state)

      assert signal == {:sell, 1.0}
      assert new_state.position == nil
      assert length(new_state.trades) == 1
      assert hd(new_state.trades).exit_reason == :stop_loss
    end

    test "tracks stop loss exits" do
      {:ok, state} = Momentum.init(%{})

      trades = [
        %{return: 0.10, exit_reason: :momentum},
        %{return: -0.05, exit_reason: :stop_loss},
        %{return: -0.08, exit_reason: :stop_loss}
      ]

      state = %{state | trades: trades}
      {:ok, stats} = Momentum.on_complete(state)

      assert stats.stop_loss_exits == 2
    end
  end

  # Helper function
  defp make_price_data(yes_price) do
    %{
      yes_price: yes_price,
      no_price: 1.0 - yes_price,
      volume: 1000.0,
      liquidity: 5000.0,
      timestamp: DateTime.utc_now()
    }
  end
end
