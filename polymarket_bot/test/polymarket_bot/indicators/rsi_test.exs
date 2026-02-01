defmodule PolymarketBot.Indicators.RSITest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Indicators.RSI

  describe "compute_rsi/2" do
    test "returns nil when not enough data" do
      assert RSI.compute_rsi([1, 2, 3], 14) == nil
      assert RSI.compute_rsi([], 5) == nil
    end

    test "returns 100 when all gains (no losses)" do
      # 15 prices with only gains
      prices = Enum.to_list(1..15)
      assert RSI.compute_rsi(prices, 14) == 100.0
    end

    test "returns 0 when all losses (no gains)" do
      # 15 prices with only losses
      prices = Enum.to_list(15..1) |> Enum.map(&(&1 * 1.0))
      assert RSI.compute_rsi(prices, 14) == 0.0
    end

    test "returns around 50 for equal gains and losses" do
      # Alternating up and down
      prices = [10, 11, 10, 11, 10, 11, 10, 11, 10, 11, 10, 11, 10, 11, 10]
      rsi = RSI.compute_rsi(prices, 14)

      assert rsi >= 45.0 and rsi <= 55.0
    end

    test "is clamped between 0 and 100" do
      prices = Enum.to_list(1..20) |> Enum.map(&(&1 * 1.0))
      rsi = RSI.compute_rsi(prices, 5)

      assert rsi >= 0.0 and rsi <= 100.0
    end
  end

  describe "compute_rsi_series/2" do
    test "returns list of same length as input" do
      prices = Enum.to_list(1..20) |> Enum.map(&(&1 * 1.0))
      series = RSI.compute_rsi_series(prices, 5)

      assert length(series) == 20
    end

    test "early elements are nil until enough data" do
      prices = Enum.to_list(1..10) |> Enum.map(&(&1 * 1.0))
      series = RSI.compute_rsi_series(prices, 5)

      # Need period + 1 = 6 prices for first RSI
      assert Enum.at(series, 4) == nil
      assert Enum.at(series, 5) != nil
    end
  end

  describe "sma/2" do
    test "returns nil when not enough data" do
      assert RSI.sma([1, 2], 3) == nil
    end

    test "computes correct SMA" do
      # SMA of last 3: (3 + 4 + 5) / 3 = 4.0
      assert RSI.sma([1, 2, 3, 4, 5], 3) == 4.0
    end

    test "handles single period" do
      assert RSI.sma([1, 2, 3], 1) == 3.0
    end
  end

  describe "slope_last/2" do
    test "returns nil when not enough data" do
      assert RSI.slope_last([1, 2], 3) == nil
    end

    test "computes correct slope" do
      # Slope = (5 - 3) / (3 - 1) = 1.0
      assert RSI.slope_last([1, 2, 3, 4, 5], 3) == 1.0
    end

    test "handles negative slope" do
      assert RSI.slope_last([5, 4, 3], 3) == -1.0
    end
  end
end
