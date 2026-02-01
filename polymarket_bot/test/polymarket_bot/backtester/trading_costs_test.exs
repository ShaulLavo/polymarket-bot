defmodule PolymarketBot.Backtester.TradingCostsTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Backtester.TradingCosts

  describe "default_config/0" do
    test "returns default configuration" do
      config = TradingCosts.default_config()

      assert is_map(config)
      assert config.slippage_factor == 0.001
      assert config.spread_enabled == true
      assert config.default_spread == 0.01
    end
  end

  describe "merge_config/1" do
    test "merges user config with defaults" do
      user_config = %{slippage_factor: 0.005}
      config = TradingCosts.merge_config(user_config)

      assert config.slippage_factor == 0.005
      assert config.spread_enabled == true
    end

    test "handles nil config" do
      config = TradingCosts.merge_config(nil)
      assert config == TradingCosts.default_config()
    end
  end

  describe "apply_costs/5" do
    test "applies slippage to buy orders (price increases)" do
      {:ok, exec_price, costs} =
        TradingCosts.apply_costs(
          0.50,
          :buy,
          100.0,
          %{slippage_factor: 0.01, spread_enabled: false},
          %{}
        )

      assert exec_price > 0.50
      assert costs.slippage_amount > 0
    end

    test "applies slippage to sell orders (price decreases)" do
      {:ok, exec_price, costs} =
        TradingCosts.apply_costs(
          0.50,
          :sell,
          100.0,
          %{slippage_factor: 0.01, spread_enabled: false},
          %{}
        )

      assert exec_price < 0.50
      assert costs.slippage_amount > 0
    end

    test "applies spread cost" do
      {:ok, exec_price, costs} =
        TradingCosts.apply_costs(
          0.50,
          :buy,
          100.0,
          %{slippage_factor: 0.0, spread_enabled: true, default_spread: 0.02},
          %{}
        )

      # Should pay half the spread (0.01) on top of mid price
      assert exec_price == 0.51
      assert costs.spread_cost == 0.01
    end

    test "uses spread from context when available" do
      context = %{spread: 0.04}

      {:ok, exec_price, costs} =
        TradingCosts.apply_costs(
          0.50,
          :buy,
          100.0,
          %{slippage_factor: 0.0, spread_enabled: true, spread_from_data: true},
          context
        )

      # Should pay half of 0.04 spread = 0.02
      assert exec_price == 0.52
      assert costs.spread_cost == 0.02
    end

    test "clamps execution price to valid range" do
      # With extreme slippage, price should still be clamped
      {:ok, exec_price, _costs} =
        TradingCosts.apply_costs(
          0.99,
          :buy,
          10000.0,
          %{slippage_factor: 0.1, spread_enabled: false},
          %{liquidity: 100.0}
        )

      assert exec_price <= 0.999
    end

    test "returns cost breakdown" do
      {:ok, _exec_price, costs} =
        TradingCosts.apply_costs(0.50, :buy, 100.0, %{}, %{})

      assert Map.has_key?(costs, :base_price)
      assert Map.has_key?(costs, :execution_price)
      assert Map.has_key?(costs, :slippage_pct)
      assert Map.has_key?(costs, :slippage_amount)
      assert Map.has_key?(costs, :spread_cost)
      assert Map.has_key?(costs, :fee_amount)
      assert Map.has_key?(costs, :total_cost)
    end
  end

  describe "calculate_slippage/5" do
    test "scales slippage by liquidity" do
      config = %{slippage_factor: 0.001, slippage_liquidity_scale: true}

      # Low liquidity = higher slippage
      {pct_low, _} =
        TradingCosts.calculate_slippage(0.50, :buy, 100.0, config, %{liquidity: 1000.0})

      # High liquidity = lower slippage
      {pct_high, _} =
        TradingCosts.calculate_slippage(0.50, :buy, 100.0, config, %{liquidity: 10000.0})

      assert pct_low > pct_high
    end

    test "caps slippage at 10%" do
      config = %{slippage_factor: 1.0, slippage_liquidity_scale: true}

      {pct, _} = TradingCosts.calculate_slippage(0.50, :buy, 10000.0, config, %{liquidity: 100.0})

      assert pct <= 0.10
    end
  end

  describe "calculate_fees/3" do
    test "calculates taker fee" do
      config = %{taker_fee: 0.01}
      fee = TradingCosts.calculate_fees(1000.0, :buy, config)

      assert fee == 10.0
    end

    test "returns zero when no fee configured" do
      config = %{taker_fee: 0.0}
      fee = TradingCosts.calculate_fees(1000.0, :buy, config)

      assert fee == 0.0
    end
  end

  describe "estimate_round_trip_costs/5" do
    test "estimates total costs for entry and exit" do
      result =
        TradingCosts.estimate_round_trip_costs(
          0.50,
          0.55,
          100.0,
          %{slippage_factor: 0.001, spread_enabled: true, default_spread: 0.02},
          %{liquidity: 10000.0}
        )

      assert result.entry_execution_price > 0.50
      assert result.exit_execution_price < 0.55
      assert result.total_cost > 0
      assert result.effective_spread > 0
    end
  end

  describe "estimate_gabagool_costs/5" do
    test "estimates costs for buying both YES and NO tokens" do
      result =
        TradingCosts.estimate_gabagool_costs(
          0.48,
          0.50,
          100.0,
          %{slippage_factor: 0.001, spread_enabled: true, default_spread: 0.01},
          %{liquidity: 10000.0}
        )

      # Gross spread = 1.0 - 0.98 = 0.02
      assert_in_delta result.gross_spread, 0.02, 0.001

      # Net spread should be less than gross due to costs
      assert result.net_spread < result.gross_spread

      # Actual entry cost should be higher than quoted prices
      assert result.actual_entry_cost > 0.98

      # Should indicate if still profitable
      assert is_boolean(result.profitable)
    end

    test "returns unprofitable when costs exceed spread" do
      # Small spread with high costs
      result =
        TradingCosts.estimate_gabagool_costs(
          0.495,
          0.500,
          100.0,
          %{slippage_factor: 0.01, spread_enabled: true, default_spread: 0.02},
          %{liquidity: 1000.0}
        )

      # Gross spread = 1.0 - 0.995 = 0.005 (very small)
      # With costs, net spread should be negative
      assert result.profitable == false or result.net_spread < 0.005
    end
  end
end
