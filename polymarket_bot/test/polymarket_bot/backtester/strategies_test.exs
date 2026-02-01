defmodule PolymarketBot.Backtester.StrategiesTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Backtester.Strategies.{GabagoolArb, MeanReversion, Momentum}

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

  describe "GabagoolArb" do
    test "initializes with default config" do
      {:ok, state} = GabagoolArb.init(%{})

      assert state.config.entry_threshold == 0.02
      assert state.config.position_size == 1.0
      assert state.config.max_positions == 5
      assert state.positions == []
      assert state.opportunities_found == 0
    end

    test "holds when spread is below threshold" do
      {:ok, state} = GabagoolArb.init(%{entry_threshold: 0.02})

      # YES + NO = 0.99, spread = 0.01 (below 0.02 threshold)
      price_data = make_arb_price_data(0.50, 0.49)
      {signal, new_state} = GabagoolArb.on_price(price_data, state)

      assert signal == :hold
      assert new_state.opportunities_found == 0
      assert new_state.positions == []
    end

    test "buys when spread exceeds threshold" do
      {:ok, state} = GabagoolArb.init(%{entry_threshold: 0.02, position_size: 1.0})

      # YES + NO = 0.97, spread = 0.03 (above 0.02 threshold)
      price_data = make_arb_price_data(0.48, 0.49)
      {signal, new_state} = GabagoolArb.on_price(price_data, state)

      assert signal == {:buy, 1.0}
      assert new_state.opportunities_found == 1
      assert length(new_state.positions) == 1

      [position] = new_state.positions
      assert position.yes_price == 0.48
      assert position.no_price == 0.49
      assert_in_delta position.spread, 0.03, 0.0001
    end

    test "respects max_positions limit" do
      {:ok, state} = GabagoolArb.init(%{entry_threshold: 0.02, max_positions: 2})

      # Fill up positions
      price_data = make_arb_price_data(0.48, 0.49)

      {_signal, state} = GabagoolArb.on_price(price_data, state)
      {_signal, state} = GabagoolArb.on_price(price_data, state)

      assert length(state.positions) == 2

      # Third opportunity should be ignored
      {signal, final_state} = GabagoolArb.on_price(price_data, state)

      assert signal == :hold
      assert length(final_state.positions) == 2
      assert final_state.opportunities_found == 2
    end

    test "tracks multiple opportunities correctly" do
      {:ok, state} = GabagoolArb.init(%{entry_threshold: 0.01, max_positions: 10})

      spreads = [{0.48, 0.49}, {0.45, 0.52}, {0.40, 0.55}]

      final_state =
        Enum.reduce(spreads, state, fn {yes, no}, acc ->
          {_signal, new_state} = GabagoolArb.on_price(make_arb_price_data(yes, no), acc)
          new_state
        end)

      assert final_state.opportunities_found == 3
      assert length(final_state.positions) == 3
      assert length(final_state.spreads_captured) == 3
    end

    test "on_complete calculates correct statistics" do
      {:ok, state} = GabagoolArb.init(%{entry_threshold: 0.01})

      # Add some positions manually
      positions = [
        %{
          yes_price: 0.48,
          no_price: 0.49,
          total_cost: 0.97,
          spread: 0.03,
          entry_timestamp: DateTime.utc_now()
        },
        %{
          yes_price: 0.45,
          no_price: 0.50,
          total_cost: 0.95,
          spread: 0.05,
          entry_timestamp: DateTime.utc_now()
        }
      ]

      state = %{
        state
        | positions: positions,
          spreads_captured: [0.03, 0.05],
          opportunities_found: 2
      }

      {:ok, stats} = GabagoolArb.on_complete(state)

      assert stats.opportunities_found == 2
      assert stats.positions_held == 2
      assert stats.avg_spread == 0.04
      assert stats.theoretical_profit == 0.08
      assert stats.total_invested == 1.92
      assert stats.roi_percent == Float.round(0.08 / 1.92 * 100, 2)
    end

    test "on_complete handles empty state" do
      {:ok, state} = GabagoolArb.init(%{})

      {:ok, stats} = GabagoolArb.on_complete(state)

      assert stats.opportunities_found == 0
      assert stats.positions_held == 0
      assert stats.avg_spread == 0.0
      assert stats.theoretical_profit == 0.0
      assert stats.roi_percent == 0.0
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

  defp make_arb_price_data(yes_price, no_price) do
    %{
      yes_price: yes_price,
      no_price: no_price,
      volume: 1000.0,
      liquidity: 5000.0,
      timestamp: DateTime.utc_now()
    }
  end
end
