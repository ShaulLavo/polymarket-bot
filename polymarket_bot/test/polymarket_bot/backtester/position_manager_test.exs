defmodule PolymarketBot.Backtester.PositionManagerTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Backtester.PositionManager

  describe "init/1" do
    test "initializes with given capital" do
      state = PositionManager.init(10000.0)

      assert state.cash == 10000.0
      assert state.positions == []
      assert state.next_position_id == 1
      assert state.total_realized_pnl == 0.0
      assert state.equity_curve == [10000.0]
    end
  end

  describe "open_position/6" do
    test "opens a long position" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, new_state, position} =
        PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)

      assert position.id == 1
      assert position.side == :long
      assert position.entry_price == 0.50
      assert position.size == 100.0
      assert position.entry_cost == 50.0
      assert new_state.cash == 9950.0
      assert length(new_state.positions) == 1
    end

    test "returns error when insufficient funds" do
      state = PositionManager.init(100.0)
      timestamp = DateTime.utc_now()

      result = PositionManager.open_position(state, :long, 0.50, 1000.0, timestamp)

      assert result == {:error, :insufficient_funds}
    end

    test "applies trading costs when configured" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()
      costs_config = %{slippage_factor: 0.01, spread_enabled: true, default_spread: 0.02}

      {:ok, _new_state, position} =
        PositionManager.open_position(state, :long, 0.50, 100.0, timestamp,
          costs_config: costs_config
        )

      # Entry price should be higher due to costs
      assert position.entry_price > 0.50
      assert position.cost_breakdown != nil
    end

    test "increments position id" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state1, pos1} = PositionManager.open_position(state, :long, 0.50, 10.0, timestamp)
      {:ok, _state2, pos2} = PositionManager.open_position(state1, :long, 0.60, 10.0, timestamp)

      assert pos1.id == 1
      assert pos2.id == 2
    end
  end

  describe "open_gabagool_position/6" do
    test "opens arbitrage position with both YES and NO" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, new_state, position} =
        PositionManager.open_gabagool_position(state, 0.48, 0.50, 100.0, timestamp)

      assert position.side == :gabagool
      assert position.yes_entry_price == 0.48
      assert position.no_entry_price == 0.50
      assert_in_delta position.gross_spread, 0.02, 0.0001
      assert_in_delta position.net_spread, 0.02, 0.0001
      # Entry cost = (0.48 + 0.50) * 100 = 98.0
      assert position.entry_cost == 98.0
      assert new_state.cash == 10000.0 - 98.0
    end

    test "calculates costs for gabagool position" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()
      costs_config = %{slippage_factor: 0.001, spread_enabled: true, default_spread: 0.01}

      {:ok, _new_state, position} =
        PositionManager.open_gabagool_position(state, 0.48, 0.50, 100.0, timestamp,
          costs_config: costs_config
        )

      # Net spread should be less than gross spread due to costs
      assert position.net_spread < position.gross_spread
      assert position.cost_info != nil
    end
  end

  describe "close_position/5" do
    test "closes position and realizes P&L" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _position} =
        PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)

      # Close at higher price (profit)
      {:ok, new_state, closed} =
        PositionManager.close_position(state, 1, 0.60, timestamp)

      assert closed.exit_price == 0.60
      assert closed.realized_pnl > 0
      assert new_state.positions == []
      assert new_state.total_realized_pnl > 0
      # Cash should increase by entry cost + profit
      assert new_state.cash > state.cash
    end

    test "returns error for non-existent position" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      result = PositionManager.close_position(state, 999, 0.50, timestamp)

      assert result == {:error, :position_not_found}
    end
  end

  describe "close_all_positions/4" do
    test "closes all open positions" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 50.0, timestamp)
      {:ok, state, _} = PositionManager.open_position(state, :long, 0.60, 50.0, timestamp)

      assert length(state.positions) == 2

      {:ok, new_state, closed} =
        PositionManager.close_all_positions(state, 0.55, timestamp)

      assert new_state.positions == []
      assert length(closed) == 2
    end
  end

  describe "update_unrealized_pnl/3" do
    test "updates unrealized P&L for long positions" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)

      # Price increased
      new_state = PositionManager.update_unrealized_pnl(state, 0.60)

      [position] = new_state.positions
      assert position.unrealized_pnl > 0
      assert position.current_price == 0.60
    end

    test "updates equity curve" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)

      initial_curve_length = length(state.equity_curve)
      new_state = PositionManager.update_unrealized_pnl(state, 0.60)

      assert length(new_state.equity_curve) == initial_curve_length + 1
    end
  end

  describe "get_total_equity/1" do
    test "returns cash plus position values" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)
      # Entry cost = 50.0, so cash = 9950.0

      equity = PositionManager.get_total_equity(state)

      # Total equity = cash + position value = 9950 + 50 = 10000 (no P&L yet)
      assert equity == 10000.0
    end

    test "includes unrealized P&L" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)
      state = PositionManager.update_unrealized_pnl(state, 0.60)

      equity = PositionManager.get_total_equity(state)

      # Should be more than initial due to unrealized gains
      assert equity > 10000.0
    end
  end

  describe "get_open_position_count/1" do
    test "returns number of open positions" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      assert PositionManager.get_open_position_count(state) == 0

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 10.0, timestamp)
      assert PositionManager.get_open_position_count(state) == 1

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.60, 10.0, timestamp)
      assert PositionManager.get_open_position_count(state) == 2
    end
  end

  describe "scale_in/6" do
    test "adds to existing position" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)

      {:ok, new_state, updated} =
        PositionManager.scale_in(state, 1, 50.0, 0.60, timestamp)

      assert updated.size == 150.0
      # Average price should be between 0.50 and 0.60
      assert updated.entry_price > 0.50
      assert updated.entry_price < 0.60
      assert new_state.cash < state.cash
    end

    test "returns error for non-existent position" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      result = PositionManager.scale_in(state, 999, 50.0, 0.60, timestamp)

      assert result == {:error, :position_not_found}
    end
  end

  describe "scale_out/6" do
    test "reduces position size" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)

      {:ok, new_state, updated} =
        PositionManager.scale_out(state, 1, 50.0, 0.60, timestamp)

      assert updated.size == 50.0
      assert new_state.cash > state.cash
      assert new_state.total_realized_pnl > 0
    end

    test "closes entire position when scaling out full size" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)

      {:ok, new_state, closed} =
        PositionManager.scale_out(state, 1, 100.0, 0.60, timestamp)

      assert closed.exit_price == 0.60
      assert new_state.positions == []
    end
  end

  describe "get_summary/1" do
    test "returns comprehensive summary" do
      state = PositionManager.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, state, _} = PositionManager.open_position(state, :long, 0.50, 100.0, timestamp)
      state = PositionManager.update_unrealized_pnl(state, 0.55)

      summary = PositionManager.get_summary(state)

      assert Map.has_key?(summary, :cash)
      assert Map.has_key?(summary, :total_equity)
      assert Map.has_key?(summary, :open_positions)
      assert Map.has_key?(summary, :total_position_cost)
      assert Map.has_key?(summary, :total_unrealized_pnl)
      assert Map.has_key?(summary, :total_realized_pnl)
      assert Map.has_key?(summary, :total_pnl)

      assert summary.open_positions == 1
      assert summary.total_unrealized_pnl > 0
    end
  end
end
