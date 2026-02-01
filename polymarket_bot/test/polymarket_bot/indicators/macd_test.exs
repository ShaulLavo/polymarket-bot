defmodule PolymarketBot.Indicators.MACDTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Indicators.MACD

  describe "ema/2" do
    test "returns nil when not enough data" do
      assert MACD.ema([1, 2], 5) == nil
      assert MACD.ema([], 3) == nil
    end

    test "computes EMA correctly" do
      values = [1, 2, 3, 4, 5]
      ema = MACD.ema(values, 3)

      # EMA with k = 2/(3+1) = 0.5
      # EMA[0] = 1
      # EMA[1] = 2 * 0.5 + 1 * 0.5 = 1.5
      # EMA[2] = 3 * 0.5 + 1.5 * 0.5 = 2.25
      # EMA[3] = 4 * 0.5 + 2.25 * 0.5 = 3.125
      # EMA[4] = 5 * 0.5 + 3.125 * 0.5 = 4.0625
      assert_in_delta ema, 4.0625, 0.001
    end

    test "EMA with period 1 equals last value" do
      assert MACD.ema([1, 2, 3, 4, 5], 1) == 5.0
    end
  end

  describe "compute_macd/4" do
    test "returns nil when not enough data" do
      # Need slow + signal = 26 + 9 = 35 minimum
      prices = Enum.to_list(1..30)
      assert MACD.compute_macd(prices, 12, 26, 9) == nil
    end

    test "returns map with all required keys" do
      prices = Enum.to_list(1..50) |> Enum.map(&(&1 * 1.0))
      result = MACD.compute_macd(prices, 12, 26, 9)

      assert is_map(result)
      assert Map.has_key?(result, :macd)
      assert Map.has_key?(result, :signal)
      assert Map.has_key?(result, :hist)
      assert Map.has_key?(result, :hist_delta)
    end

    test "MACD line is fast EMA minus slow EMA" do
      prices = Enum.to_list(1..50) |> Enum.map(&(&1 * 1.0))
      result = MACD.compute_macd(prices, 12, 26, 9)

      fast_ema = MACD.ema(prices, 12)
      slow_ema = MACD.ema(prices, 26)

      assert_in_delta result.macd, fast_ema - slow_ema, 0.001
    end

    test "histogram is MACD minus signal" do
      prices = Enum.to_list(1..50) |> Enum.map(&(&1 * 1.0))
      result = MACD.compute_macd(prices, 12, 26, 9)

      assert_in_delta result.hist, result.macd - result.signal, 0.001
    end

    test "hist_delta shows change from previous bar" do
      # Use prices that will produce a measurable delta
      prices = Enum.to_list(1..51) |> Enum.map(&(&1 * 1.0))
      result = MACD.compute_macd(prices, 12, 26, 9)

      # hist_delta should be non-nil with enough data
      assert result.hist_delta != nil
    end

    test "positive trend produces positive MACD line" do
      # Steadily increasing prices
      prices = Enum.to_list(1..50) |> Enum.map(&(&1 * 1.0))
      result = MACD.compute_macd(prices, 12, 26, 9)

      # Fast EMA should be higher than slow EMA in uptrend
      assert result.macd > 0
    end

    test "negative trend produces negative MACD line" do
      # Steadily decreasing prices
      prices = Enum.to_list(50..1) |> Enum.map(&(&1 * 1.0))
      result = MACD.compute_macd(prices, 12, 26, 9)

      # Fast EMA should be lower than slow EMA in downtrend
      assert result.macd < 0
    end
  end
end
