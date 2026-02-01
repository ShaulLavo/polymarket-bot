defmodule PolymarketBot.Engines.EdgeTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Engines.Edge

  describe "compute_edge/1" do
    test "returns nils when market data is missing" do
      result = Edge.compute_edge(%{model_up: 0.7, model_down: 0.3})

      assert result.market_up == nil
      assert result.market_down == nil
      assert result.edge_up == nil
      assert result.edge_down == nil
    end

    test "normalizes market prices" do
      result =
        Edge.compute_edge(%{
          model_up: 0.7,
          model_down: 0.3,
          market_yes: 0.6,
          market_no: 0.4
        })

      assert result.market_up == 0.6
      assert result.market_down == 0.4
    end

    test "computes edge correctly" do
      result =
        Edge.compute_edge(%{
          model_up: 0.7,
          model_down: 0.3,
          market_yes: 0.5,
          market_no: 0.5
        })

      # edge_up = 0.7 - 0.5 = 0.2
      assert_in_delta result.edge_up, 0.2, 0.001
      # edge_down = 0.3 - 0.5 = -0.2
      assert_in_delta result.edge_down, -0.2, 0.001
    end

    test "handles non-normalized market prices" do
      result =
        Edge.compute_edge(%{
          model_up: 0.7,
          model_down: 0.3,
          market_yes: 55.0,
          market_no: 45.0
        })

      # Normalized: market_up = 55/100 = 0.55
      assert_in_delta result.market_up, 0.55, 0.001
      assert_in_delta result.market_down, 0.45, 0.001
    end

    test "returns nils when sum is zero" do
      result =
        Edge.compute_edge(%{
          model_up: 0.7,
          model_down: 0.3,
          market_yes: 0.0,
          market_no: 0.0
        })

      assert result.market_up == nil
      assert result.edge_up == nil
    end
  end

  describe "decide/1" do
    test "returns no_trade when edge data is missing" do
      result = Edge.decide(%{remaining_minutes: 12.0})

      assert result.action == :no_trade
      assert result.side == nil
      assert result.reason == "missing_market_data"
    end

    test "EARLY phase requires 5% edge" do
      # Edge below threshold
      result =
        Edge.decide(%{
          remaining_minutes: 12.0,
          edge_up: 0.04,
          edge_down: 0.02,
          model_up: 0.6,
          model_down: 0.4
        })

      assert result.action == :no_trade
      assert result.phase == :early
      assert result.reason == "edge_below_0.05"

      # Edge above threshold
      result =
        Edge.decide(%{
          remaining_minutes: 12.0,
          edge_up: 0.06,
          edge_down: 0.02,
          model_up: 0.6,
          model_down: 0.4
        })

      assert result.action == :enter
      assert result.phase == :early
      assert result.side == :up
    end

    test "MID phase requires 10% edge" do
      # Edge below threshold
      result =
        Edge.decide(%{
          remaining_minutes: 7.0,
          edge_up: 0.08,
          edge_down: 0.02,
          model_up: 0.65,
          model_down: 0.35
        })

      assert result.action == :no_trade
      assert result.phase == :mid
      assert result.reason == "edge_below_0.1"

      # Edge above threshold
      result =
        Edge.decide(%{
          remaining_minutes: 7.0,
          edge_up: 0.12,
          edge_down: 0.02,
          model_up: 0.65,
          model_down: 0.35
        })

      assert result.action == :enter
      assert result.phase == :mid
    end

    test "LATE phase requires 20% edge" do
      # Edge below threshold
      result =
        Edge.decide(%{
          remaining_minutes: 3.0,
          edge_up: 0.15,
          edge_down: 0.02,
          model_up: 0.7,
          model_down: 0.3
        })

      assert result.action == :no_trade
      assert result.phase == :late
      assert result.reason == "edge_below_0.2"

      # Edge above threshold
      result =
        Edge.decide(%{
          remaining_minutes: 3.0,
          edge_up: 0.25,
          edge_down: 0.02,
          model_up: 0.7,
          model_down: 0.3
        })

      assert result.action == :enter
      assert result.phase == :late
    end

    test "rejects if model probability below minimum" do
      result =
        Edge.decide(%{
          remaining_minutes: 12.0,
          edge_up: 0.10,
          edge_down: 0.02,
          model_up: 0.52,
          model_down: 0.48
        })

      # EARLY phase requires min_prob 0.55
      assert result.action == :no_trade
      assert result.reason == "prob_below_0.55"
    end

    test "chooses side with higher edge" do
      result =
        Edge.decide(%{
          remaining_minutes: 12.0,
          edge_up: 0.05,
          edge_down: 0.08,
          model_up: 0.4,
          model_down: 0.6
        })

      assert result.side == :down
    end

    test "assigns strength based on edge magnitude" do
      # OPTIONAL: edge < 0.10
      result =
        Edge.decide(%{
          remaining_minutes: 12.0,
          edge_up: 0.06,
          edge_down: 0.02,
          model_up: 0.6,
          model_down: 0.4
        })

      assert result.strength == :optional

      # GOOD: 0.10 <= edge < 0.20
      result =
        Edge.decide(%{
          remaining_minutes: 12.0,
          edge_up: 0.15,
          edge_down: 0.02,
          model_up: 0.65,
          model_down: 0.35
        })

      assert result.strength == :good

      # STRONG: edge >= 0.20
      result =
        Edge.decide(%{
          remaining_minutes: 12.0,
          edge_up: 0.25,
          edge_down: 0.02,
          model_up: 0.7,
          model_down: 0.3
        })

      assert result.strength == :strong
    end
  end
end
