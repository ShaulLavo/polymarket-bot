defmodule PolymarketBot.Data.BinanceHistoricalTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Data.BinanceHistorical

  # These tests are integration tests that hit the real Binance API
  @moduletag :external

  describe "fetch_historical/1" do
    @tag :external
    test "fetches historical klines with start_time" do
      start = DateTime.add(DateTime.utc_now(), -1, :hour)

      {:ok, candles} = BinanceHistorical.fetch_historical(interval: "1m", start_time: start)

      assert length(candles) > 0

      candle = List.first(candles)
      assert is_integer(candle.open_time)
      assert is_float(candle.open)
      assert Map.has_key?(candle, :quote_volume)
      assert Map.has_key?(candle, :trades)
    end

    @tag :external
    test "respects time range" do
      start = DateTime.add(DateTime.utc_now(), -30, :minute)
      end_time = DateTime.add(DateTime.utc_now(), -15, :minute)

      {:ok, candles} =
        BinanceHistorical.fetch_historical(
          interval: "1m",
          start_time: start,
          end_time: end_time
        )

      # Should have approximately 15 candles
      assert length(candles) >= 10 and length(candles) <= 20
    end
  end

  describe "fetch_last_n_days/1" do
    @tag :external
    test "fetches multiple days of data" do
      {:ok, candles} = BinanceHistorical.fetch_last_n_days(days: 1, interval: "15m")

      # 24 hours * 4 (15-min intervals) = 96 candles per day
      assert length(candles) >= 90
    end
  end

  describe "group_into_windows/2" do
    test "groups candles by 15-minute windows" do
      # Create test candles spanning 30 minutes
      base_time = 1_704_067_200_000

      candles = [
        %{open_time: base_time, close: 100.0, open: 99.0, high: 101.0, low: 98.0, volume: 100.0},
        %{
          open_time: base_time + 60_000,
          close: 101.0,
          open: 100.0,
          high: 102.0,
          low: 99.0,
          volume: 110.0
        },
        %{
          open_time: base_time + 15 * 60_000,
          close: 102.0,
          open: 101.0,
          high: 103.0,
          low: 100.0,
          volume: 120.0
        },
        %{
          open_time: base_time + 16 * 60_000,
          close: 103.0,
          open: 102.0,
          high: 104.0,
          low: 101.0,
          volume: 130.0
        }
      ]

      windows = BinanceHistorical.group_into_windows(candles, 15)

      assert length(windows) == 2

      [w1, w2] = windows
      assert length(w1.candles) == 2
      assert length(w2.candles) == 2
    end
  end

  describe "aggregate_candles/1" do
    test "aggregates candles correctly" do
      candles = [
        %{
          open_time: 1000,
          open: 100.0,
          high: 105.0,
          low: 98.0,
          close: 103.0,
          volume: 100.0,
          close_time: 1999
        },
        %{
          open_time: 2000,
          open: 103.0,
          high: 108.0,
          low: 102.0,
          close: 107.0,
          volume: 150.0,
          close_time: 2999
        },
        %{
          open_time: 3000,
          open: 107.0,
          high: 110.0,
          low: 105.0,
          close: 109.0,
          volume: 200.0,
          close_time: 3999
        }
      ]

      result = BinanceHistorical.aggregate_candles(candles)

      assert result.open_time == 1000
      assert result.open == 100.0
      assert result.high == 110.0
      assert result.low == 98.0
      assert result.close == 109.0
      assert result.volume == 450.0
      assert result.close_time == 3999
    end

    test "returns nil for empty list" do
      assert BinanceHistorical.aggregate_candles([]) == nil
    end
  end
end
