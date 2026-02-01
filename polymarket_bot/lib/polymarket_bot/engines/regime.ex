defmodule PolymarketBot.Engines.Regime do
  @moduledoc """
  Market regime detection engine.

  Classifies the current market structure into one of four regimes:
  - `:trend_up` - Price above VWAP with positive slope
  - `:trend_down` - Price below VWAP with negative slope
  - `:range` - Frequent VWAP crosses or mixed signals
  - `:chop` - Low volume, flat market
  """

  @type regime :: :trend_up | :trend_down | :range | :chop

  @type result :: %{
          regime: regime(),
          reason: String.t()
        }

  @doc """
  Detects the current market regime based on price action and volume.

  ## Parameters

  Map with:
  - `:price` - Current price
  - `:vwap` - Current VWAP value
  - `:vwap_slope` - Slope of VWAP
  - `:vwap_cross_count` - Number of VWAP crosses in session (optional)
  - `:volume_recent` - Recent volume (optional)
  - `:volume_avg` - Average volume (optional)

  ## Returns

  Map with:
  - `:regime` - One of :trend_up, :trend_down, :range, :chop
  - `:reason` - Explanation for the classification

  ## Regime Logic

  1. If missing required inputs -> :chop
  2. If low volume (< 60% avg) and price flat near VWAP -> :chop
  3. If price above VWAP and slope positive -> :trend_up
  4. If price below VWAP and slope negative -> :trend_down
  5. If 3+ VWAP crosses -> :range
  6. Default -> :range

  """
  @spec detect_regime(map()) :: result()
  def detect_regime(inputs) when is_map(inputs) do
    price = Map.get(inputs, :price)
    vwap = Map.get(inputs, :vwap)
    vwap_slope = Map.get(inputs, :vwap_slope)
    vwap_cross_count = Map.get(inputs, :vwap_cross_count)
    volume_recent = Map.get(inputs, :volume_recent)
    volume_avg = Map.get(inputs, :volume_avg)

    # Check for missing required inputs
    if is_nil(price) or is_nil(vwap) or is_nil(vwap_slope) do
      %{regime: :chop, reason: "missing_inputs"}
    else
      above_vwap = price > vwap

      # Check for low volume chop
      if low_volume_chop?(price, vwap, volume_recent, volume_avg) do
        %{regime: :chop, reason: "low_volume_flat"}
      else
        cond do
          # Range: frequent VWAP crosses (check first - overrides trend)
          is_integer(vwap_cross_count) and vwap_cross_count >= 3 ->
            %{regime: :range, reason: "frequent_vwap_cross"}

          # Trend up: price above VWAP with positive slope
          above_vwap and vwap_slope > 0 ->
            %{regime: :trend_up, reason: "price_above_vwap_slope_up"}

          # Trend down: price below VWAP with negative slope
          not above_vwap and vwap_slope < 0 ->
            %{regime: :trend_down, reason: "price_below_vwap_slope_down"}

          # Default to range
          true ->
            %{regime: :range, reason: "default"}
        end
      end
    end
  end

  def detect_regime(_), do: %{regime: :chop, reason: "invalid_inputs"}

  @doc """
  Checks if the regime is suitable for trading.

  Trending regimes (:trend_up, :trend_down) are generally more
  favorable for directional trades than :range or :chop.
  """
  @spec tradeable_regime?(regime()) :: boolean()
  def tradeable_regime?(:trend_up), do: true
  def tradeable_regime?(:trend_down), do: true
  def tradeable_regime?(:range), do: true
  def tradeable_regime?(:chop), do: false

  @doc """
  Returns a suggested position bias based on regime.

  - :trend_up -> :long
  - :trend_down -> :short
  - :range, :chop -> :neutral
  """
  @spec regime_bias(regime()) :: :long | :short | :neutral
  def regime_bias(:trend_up), do: :long
  def regime_bias(:trend_down), do: :short
  def regime_bias(_), do: :neutral

  # Private helpers

  defp low_volume_chop?(price, vwap, volume_recent, volume_avg) do
    # Check if we have volume data
    has_volume = not is_nil(volume_recent) and not is_nil(volume_avg) and volume_avg > 0

    if has_volume do
      low_volume = volume_recent < 0.6 * volume_avg
      # Price is flat near VWAP (within 0.1%)
      flat_price = abs((price - vwap) / vwap) < 0.001
      low_volume and flat_price
    else
      false
    end
  end
end
