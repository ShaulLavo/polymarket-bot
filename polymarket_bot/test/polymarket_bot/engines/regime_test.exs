defmodule PolymarketBot.Engines.RegimeTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Engines.Regime

  describe "detect_regime/1" do
    test "returns chop for missing inputs" do
      result = Regime.detect_regime(%{})

      assert result.regime == :chop
      assert result.reason == "missing_inputs"
    end

    test "returns chop when required fields are nil" do
      result = Regime.detect_regime(%{price: 100.0, vwap: nil, vwap_slope: 0.5})

      assert result.regime == :chop
      assert result.reason == "missing_inputs"
    end

    test "detects trend_up when price above VWAP with positive slope" do
      result =
        Regime.detect_regime(%{
          price: 101.0,
          vwap: 100.0,
          vwap_slope: 0.5
        })

      assert result.regime == :trend_up
      assert result.reason == "price_above_vwap_slope_up"
    end

    test "detects trend_down when price below VWAP with negative slope" do
      result =
        Regime.detect_regime(%{
          price: 99.0,
          vwap: 100.0,
          vwap_slope: -0.5
        })

      assert result.regime == :trend_down
      assert result.reason == "price_below_vwap_slope_down"
    end

    test "detects range with frequent VWAP crosses" do
      result =
        Regime.detect_regime(%{
          price: 100.5,
          vwap: 100.0,
          vwap_slope: 0.1,
          vwap_cross_count: 5
        })

      # Even though price > vwap and slope > 0, frequent crosses = range
      assert result.regime == :range
      assert result.reason == "frequent_vwap_cross"
    end

    test "detects chop with low volume and flat price" do
      result =
        Regime.detect_regime(%{
          price: 100.0,
          vwap: 100.0,
          vwap_slope: 0.0,
          volume_recent: 50.0,
          volume_avg: 100.0
        })

      assert result.regime == :chop
      assert result.reason == "low_volume_flat"
    end

    test "returns range as default" do
      result =
        Regime.detect_regime(%{
          price: 101.0,
          vwap: 100.0,
          vwap_slope: -0.1
        })

      # Price above VWAP but slope negative = mixed signals
      assert result.regime == :range
      assert result.reason == "default"
    end

    test "handles invalid inputs" do
      result = Regime.detect_regime("invalid")

      assert result.regime == :chop
      assert result.reason == "invalid_inputs"
    end
  end

  describe "tradeable_regime?/1" do
    test "trend_up is tradeable" do
      assert Regime.tradeable_regime?(:trend_up) == true
    end

    test "trend_down is tradeable" do
      assert Regime.tradeable_regime?(:trend_down) == true
    end

    test "range is tradeable" do
      assert Regime.tradeable_regime?(:range) == true
    end

    test "chop is not tradeable" do
      assert Regime.tradeable_regime?(:chop) == false
    end
  end

  describe "regime_bias/1" do
    test "trend_up returns long bias" do
      assert Regime.regime_bias(:trend_up) == :long
    end

    test "trend_down returns short bias" do
      assert Regime.regime_bias(:trend_down) == :short
    end

    test "range returns neutral bias" do
      assert Regime.regime_bias(:range) == :neutral
    end

    test "chop returns neutral bias" do
      assert Regime.regime_bias(:chop) == :neutral
    end
  end
end
