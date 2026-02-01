defmodule PolymarketBot.Engines.ProbabilityTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Engines.Probability

  describe "score_direction/1" do
    test "returns base scores with empty inputs" do
      result = Probability.score_direction(%{})

      assert result.up_score == 1
      assert result.down_score == 1
      assert result.raw_up == 0.5
    end

    test "price above VWAP adds 2 to up score" do
      result = Probability.score_direction(%{price: 101.0, vwap: 100.0})

      assert result.up_score == 3
      assert result.down_score == 1
      assert result.raw_up == 0.75
    end

    test "price below VWAP adds 2 to down score" do
      result = Probability.score_direction(%{price: 99.0, vwap: 100.0})

      assert result.up_score == 1
      assert result.down_score == 3
      assert result.raw_up == 0.25
    end

    test "positive VWAP slope adds 2 to up score" do
      result = Probability.score_direction(%{vwap_slope: 0.5})

      assert result.up_score == 3
      assert result.down_score == 1
    end

    test "negative VWAP slope adds 2 to down score" do
      result = Probability.score_direction(%{vwap_slope: -0.5})

      assert result.up_score == 1
      assert result.down_score == 3
    end

    test "RSI above 55 with positive slope adds 2 to up score" do
      result = Probability.score_direction(%{rsi: 60.0, rsi_slope: 0.5})

      assert result.up_score == 3
      assert result.down_score == 1
    end

    test "RSI below 45 with negative slope adds 2 to down score" do
      result = Probability.score_direction(%{rsi: 40.0, rsi_slope: -0.5})

      assert result.up_score == 1
      assert result.down_score == 3
    end

    test "RSI between 45-55 adds no score" do
      result = Probability.score_direction(%{rsi: 50.0, rsi_slope: 0.5})

      assert result.up_score == 1
      assert result.down_score == 1
    end

    test "expanding green MACD histogram adds 2 to up score" do
      result =
        Probability.score_direction(%{
          macd: %{hist: 0.5, hist_delta: 0.1, macd: 0.3}
        })

      # +2 for expanding green + 1 for positive MACD line
      assert result.up_score == 4
      assert result.down_score == 1
    end

    test "expanding red MACD histogram adds 2 to down score" do
      result =
        Probability.score_direction(%{
          macd: %{hist: -0.5, hist_delta: -0.1, macd: -0.3}
        })

      # +2 for expanding red + 1 for negative MACD line
      assert result.up_score == 1
      assert result.down_score == 4
    end

    test "2+ green Heiken Ashi candles adds 1 to up score" do
      result = Probability.score_direction(%{heiken_color: "green", heiken_count: 3})

      assert result.up_score == 2
      assert result.down_score == 1
    end

    test "2+ red Heiken Ashi candles adds 1 to down score" do
      result = Probability.score_direction(%{heiken_color: "red", heiken_count: 2})

      assert result.up_score == 1
      assert result.down_score == 2
    end

    test "failed VWAP reclaim adds 3 to down score" do
      result = Probability.score_direction(%{failed_vwap_reclaim: true})

      assert result.up_score == 1
      assert result.down_score == 4
    end

    test "combines multiple signals correctly" do
      result =
        Probability.score_direction(%{
          price: 101.0,
          vwap: 100.0,
          vwap_slope: 0.5,
          rsi: 60.0,
          rsi_slope: 0.5,
          heiken_color: "green",
          heiken_count: 3
        })

      # Base: 1
      # Price > VWAP: +2
      # VWAP slope > 0: +2
      # RSI > 55 + rising: +2
      # Green HA >= 2: +1
      # Total up: 8
      assert result.up_score == 8
      assert result.down_score == 1
      assert result.raw_up == 8 / 9
    end
  end

  describe "apply_time_awareness/3" do
    test "full time remaining preserves probability" do
      result = Probability.apply_time_awareness(0.7, 15.0, 15.0)

      assert result.time_decay == 1.0
      assert_in_delta result.adjusted_up, 0.7, 0.001
      assert_in_delta result.adjusted_down, 0.3, 0.001
    end

    test "no time remaining decays to 50%" do
      result = Probability.apply_time_awareness(0.8, 0.0, 15.0)

      assert result.time_decay == 0.0
      assert result.adjusted_up == 0.5
      assert result.adjusted_down == 0.5
    end

    test "half time remaining partially decays" do
      result = Probability.apply_time_awareness(0.8, 7.5, 15.0)

      assert result.time_decay == 0.5
      # adjusted = 0.5 + (0.8 - 0.5) * 0.5 = 0.5 + 0.15 = 0.65
      assert_in_delta result.adjusted_up, 0.65, 0.001
      assert_in_delta result.adjusted_down, 0.35, 0.001
    end

    test "clamps time decay between 0 and 1" do
      # More than 100% time remaining
      result = Probability.apply_time_awareness(0.7, 20.0, 15.0)
      assert result.time_decay == 1.0

      # Negative time remaining
      result = Probability.apply_time_awareness(0.7, -5.0, 15.0)
      assert result.time_decay == 0.0
    end

    test "handles invalid inputs" do
      result = Probability.apply_time_awareness(0.7, 5.0, 0.0)

      assert result.time_decay == 0.0
      assert result.adjusted_up == 0.5
      assert result.adjusted_down == 0.5
    end
  end
end
