defmodule PolymarketBot.Indicators.VWAPTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Indicators.VWAP

  describe "compute_session_vwap/1" do
    test "returns nil for empty list" do
      assert VWAP.compute_session_vwap([]) == nil
    end

    test "returns nil for non-list input" do
      assert VWAP.compute_session_vwap(nil) == nil
      assert VWAP.compute_session_vwap("invalid") == nil
    end

    test "computes correct VWAP for single candle" do
      candle = %{high: 100.0, low: 98.0, close: 99.0, volume: 1000.0}
      # Typical price = (100 + 98 + 99) / 3 = 99
      assert VWAP.compute_session_vwap([candle]) == 99.0
    end

    test "computes correct VWAP for multiple candles" do
      candles = [
        %{high: 100.0, low: 98.0, close: 99.0, volume: 1000.0},
        %{high: 102.0, low: 100.0, close: 101.0, volume: 1500.0}
      ]

      # TP1 = (100 + 98 + 99) / 3 = 99, PV1 = 99 * 1000 = 99000
      # TP2 = (102 + 100 + 101) / 3 = 101, PV2 = 101 * 1500 = 151500
      # VWAP = (99000 + 151500) / (1000 + 1500) = 250500 / 2500 = 100.2
      assert VWAP.compute_session_vwap(candles) == 100.2
    end

    test "returns nil when total volume is zero" do
      candles = [
        %{high: 100.0, low: 98.0, close: 99.0, volume: 0.0},
        %{high: 102.0, low: 100.0, close: 101.0, volume: 0.0}
      ]

      assert VWAP.compute_session_vwap(candles) == nil
    end
  end

  describe "compute_vwap_series/1" do
    test "returns empty list for empty input" do
      assert VWAP.compute_vwap_series([]) == []
    end

    test "computes running VWAP series" do
      candles = [
        %{high: 100.0, low: 98.0, close: 99.0, volume: 1000.0},
        %{high: 102.0, low: 100.0, close: 101.0, volume: 1500.0},
        %{high: 104.0, low: 102.0, close: 103.0, volume: 2000.0}
      ]

      series = VWAP.compute_vwap_series(candles)

      assert length(series) == 3
      # First element is VWAP of just first candle
      assert Enum.at(series, 0) == 99.0
      # Second element is VWAP of first two candles
      assert Enum.at(series, 1) == 100.2
    end
  end

  describe "compute_slope/2" do
    test "returns nil when not enough points" do
      assert VWAP.compute_slope([1.0, 2.0], 3) == nil
      assert VWAP.compute_slope([], 2) == nil
    end

    test "computes correct slope" do
      # Slope = (3 - 1) / (3 - 1) = 1.0
      assert VWAP.compute_slope([1.0, 2.0, 3.0], 3) == 1.0

      # Slope = (5 - 3) / (3 - 1) = 1.0
      assert VWAP.compute_slope([1.0, 2.0, 3.0, 4.0, 5.0], 3) == 1.0
    end

    test "handles negative slope" do
      assert VWAP.compute_slope([3.0, 2.0, 1.0], 3) == -1.0
    end

    test "handles flat slope" do
      assert VWAP.compute_slope([5.0, 5.0, 5.0], 3) == 0.0
    end
  end

  describe "count_crosses/2" do
    test "returns 0 for mismatched lengths" do
      assert VWAP.count_crosses([1.0, 2.0], [1.0]) == 0
    end

    test "counts crosses correctly" do
      prices = [99.0, 101.0, 99.0, 101.0]
      vwaps = [100.0, 100.0, 100.0, 100.0]

      # Crosses: below->above, above->below, below->above = 3
      assert VWAP.count_crosses(prices, vwaps) == 3
    end

    test "returns 0 when no crosses" do
      prices = [101.0, 102.0, 103.0]
      vwaps = [100.0, 100.0, 100.0]

      assert VWAP.count_crosses(prices, vwaps) == 0
    end
  end
end
