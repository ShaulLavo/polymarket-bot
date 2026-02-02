defmodule PolymarketBot.Data.BinanceTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Data.Binance

  # These tests are integration tests that hit the real Binance API
  # They are tagged as :external so they can be skipped in CI
  @moduletag :external

  describe "fetch_klines/1" do
    @tag :external
    test "fetches klines from Binance" do
      {:ok, candles} = Binance.fetch_klines(interval: "1m", limit: 5)

      assert length(candles) == 5

      candle = List.first(candles)
      assert is_integer(candle.open_time)
      assert is_float(candle.open)
      assert is_float(candle.high)
      assert is_float(candle.low)
      assert is_float(candle.close)
      assert is_float(candle.volume)
      assert is_integer(candle.close_time)
    end

    @tag :external
    test "respects limit parameter" do
      {:ok, candles} = Binance.fetch_klines(limit: 10)
      assert length(candles) == 10
    end

    @tag :external
    test "supports different intervals" do
      {:ok, candles_1m} = Binance.fetch_klines(interval: "1m", limit: 2)
      {:ok, candles_15m} = Binance.fetch_klines(interval: "15m", limit: 2)

      # Both should return valid candles
      assert length(candles_1m) == 2
      assert length(candles_15m) == 2
    end
  end

  describe "fetch_last_price/1" do
    @tag :external
    test "fetches current BTC price" do
      {:ok, price} = Binance.fetch_last_price()

      assert is_float(price)
      # BTC should be above $10,000 (sanity check)
      assert price > 10_000
    end
  end

  describe "fetch_24hr_stats/1" do
    @tag :external
    test "fetches 24hr statistics" do
      {:ok, stats} = Binance.fetch_24hr_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :high_price)
      assert Map.has_key?(stats, :low_price)
      assert Map.has_key?(stats, :volume)
    end
  end
end
