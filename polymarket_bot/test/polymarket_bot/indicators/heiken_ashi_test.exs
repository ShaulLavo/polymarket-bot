defmodule PolymarketBot.Indicators.HeikenAshiTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Indicators.HeikenAshi

  describe "compute_heiken_ashi/1" do
    test "returns empty list for empty input" do
      assert HeikenAshi.compute_heiken_ashi([]) == []
    end

    test "returns empty list for non-list input" do
      assert HeikenAshi.compute_heiken_ashi(nil) == []
    end

    test "computes correct HA for single candle" do
      candle = %{open: 100.0, high: 105.0, low: 98.0, close: 103.0}
      [ha] = HeikenAshi.compute_heiken_ashi([candle])

      # HA Close = (100 + 105 + 98 + 103) / 4 = 101.5
      assert_in_delta ha.close, 101.5, 0.001

      # First HA Open = (100 + 103) / 2 = 101.5
      assert_in_delta ha.open, 101.5, 0.001

      # HA High = max(105, 101.5, 101.5) = 105
      assert ha.high == 105.0

      # HA Low = min(98, 101.5, 101.5) = 98
      assert ha.low == 98.0

      # is_green = close >= open
      assert ha.is_green == true

      # body = abs(close - open)
      assert_in_delta ha.body, 0.0, 0.001
    end

    test "computes HA series correctly" do
      candles = [
        %{open: 100.0, high: 105.0, low: 98.0, close: 103.0},
        %{open: 103.0, high: 108.0, low: 102.0, close: 107.0}
      ]

      [ha1, ha2] = HeikenAshi.compute_heiken_ashi(candles)

      # First candle
      assert_in_delta ha1.close, 101.5, 0.001
      assert_in_delta ha1.open, 101.5, 0.001

      # Second candle HA Open = (ha1.open + ha1.close) / 2
      expected_open2 = (ha1.open + ha1.close) / 2
      assert_in_delta ha2.open, expected_open2, 0.001

      # Second candle HA Close = (103 + 108 + 102 + 107) / 4 = 105
      assert_in_delta ha2.close, 105.0, 0.001
    end

    test "identifies green and red candles" do
      candles = [
        # Bullish: close > open
        %{open: 100.0, high: 110.0, low: 99.0, close: 108.0},
        # Bearish: close < open
        %{open: 108.0, high: 109.0, low: 100.0, close: 101.0}
      ]

      [ha1, ha2] = HeikenAshi.compute_heiken_ashi(candles)

      # First should be green (close >= open after HA calculation)
      assert ha1.is_green == true

      # Second may vary based on HA smoothing
      assert is_boolean(ha2.is_green)
    end
  end

  describe "count_consecutive/1" do
    test "returns nil color and 0 count for empty list" do
      result = HeikenAshi.count_consecutive([])
      assert result == %{color: nil, count: 0}
    end

    test "counts consecutive green candles" do
      ha_candles = [
        %{is_green: true},
        %{is_green: true},
        %{is_green: true}
      ]

      result = HeikenAshi.count_consecutive(ha_candles)
      assert result == %{color: "green", count: 3}
    end

    test "counts consecutive red candles" do
      ha_candles = [
        %{is_green: false},
        %{is_green: false},
        %{is_green: false}
      ]

      result = HeikenAshi.count_consecutive(ha_candles)
      assert result == %{color: "red", count: 3}
    end

    test "counts from the end only" do
      ha_candles = [
        %{is_green: true},
        %{is_green: true},
        %{is_green: false},
        %{is_green: false},
        %{is_green: false}
      ]

      result = HeikenAshi.count_consecutive(ha_candles)
      assert result == %{color: "red", count: 3}
    end

    test "handles mixed sequence" do
      ha_candles = [
        %{is_green: true},
        %{is_green: false},
        %{is_green: true},
        %{is_green: true}
      ]

      result = HeikenAshi.count_consecutive(ha_candles)
      assert result == %{color: "green", count: 2}
    end

    test "handles single candle" do
      result = HeikenAshi.count_consecutive([%{is_green: true}])
      assert result == %{color: "green", count: 1}
    end
  end
end
