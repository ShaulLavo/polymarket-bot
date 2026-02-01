defmodule PolymarketBot.Engines.Probability do
  @moduledoc """
  Direction scoring engine for computing probability of price movement.

  Combines multiple technical indicator signals with weighted scoring
  to estimate the probability of upward vs downward price movement.
  """

  @doc """
  Scores the direction based on technical indicator inputs.

  Takes a map of indicator values and returns weighted scores for up/down.

  ## Input Map Keys

  - `:price` - Current price
  - `:vwap` - Current VWAP value
  - `:vwap_slope` - Slope of VWAP
  - `:rsi` - Current RSI value
  - `:rsi_slope` - Slope of RSI
  - `:macd` - MACD map with :macd, :hist, :hist_delta keys
  - `:heiken_color` - "green" or "red"
  - `:heiken_count` - Consecutive candle count
  - `:failed_vwap_reclaim` - Boolean for failed VWAP reclaim pattern

  ## Returns

  Map with:
  - `:up_score` - Raw weighted score for up
  - `:down_score` - Raw weighted score for down
  - `:raw_up` - Probability of up (up_score / total)

  ## Scoring Weights

  | Signal | Weight |
  |--------|--------|
  | Price > VWAP | +2 up |
  | Price < VWAP | +2 down |
  | VWAP Slope > 0 | +2 up |
  | VWAP Slope < 0 | +2 down |
  | RSI > 55 + rising | +2 up |
  | RSI < 45 + falling | +2 down |
  | MACD hist > 0, expanding | +2 up |
  | MACD hist < 0, expanding | +2 down |
  | MACD line > 0 | +1 up |
  | MACD line < 0 | +1 down |
  | 2+ green HA candles | +1 up |
  | 2+ red HA candles | +1 down |
  | Failed VWAP reclaim | +3 down |

  """
  @spec score_direction(map()) :: %{up_score: number(), down_score: number(), raw_up: float()}
  def score_direction(inputs) when is_map(inputs) do
    price = Map.get(inputs, :price)
    vwap = Map.get(inputs, :vwap)
    vwap_slope = Map.get(inputs, :vwap_slope)
    rsi = Map.get(inputs, :rsi)
    rsi_slope = Map.get(inputs, :rsi_slope)
    macd = Map.get(inputs, :macd)
    heiken_color = Map.get(inputs, :heiken_color)
    heiken_count = Map.get(inputs, :heiken_count, 0)
    failed_vwap_reclaim = Map.get(inputs, :failed_vwap_reclaim, false)

    # Start with base scores of 1
    up = 1
    down = 1

    # Price vs VWAP position (+2)
    {up, down} = score_price_vwap(up, down, price, vwap)

    # VWAP slope direction (+2)
    {up, down} = score_vwap_slope(up, down, vwap_slope)

    # RSI momentum (+2)
    {up, down} = score_rsi(up, down, rsi, rsi_slope)

    # MACD histogram expansion (+2) and line bias (+1)
    {up, down} = score_macd(up, down, macd)

    # Heiken Ashi trend continuation (+1)
    {up, down} = score_heiken_ashi(up, down, heiken_color, heiken_count)

    # Failed VWAP reclaim reversal (+3 down)
    down = if failed_vwap_reclaim == true, do: down + 3, else: down

    total = up + down
    raw_up = if total > 0, do: up / total, else: 0.5

    %{up_score: up, down_score: down, raw_up: raw_up}
  end

  @doc """
  Applies time awareness decay to the raw probability.

  As time remaining decreases, the model probability decays toward 50/50
  to reflect increasing uncertainty near expiry.

  ## Parameters

  - `raw_up` - Raw probability from score_direction
  - `remaining_minutes` - Minutes until window closes
  - `window_minutes` - Total window duration in minutes

  ## Returns

  Map with:
  - `:time_decay` - Decay factor (0 to 1)
  - `:adjusted_up` - Time-adjusted up probability
  - `:adjusted_down` - Time-adjusted down probability

  """
  @spec apply_time_awareness(float(), number(), number()) :: %{
          time_decay: float(),
          adjusted_up: float(),
          adjusted_down: float()
        }
  def apply_time_awareness(raw_up, remaining_minutes, window_minutes)
      when is_number(raw_up) and is_number(remaining_minutes) and is_number(window_minutes) and
             window_minutes > 0 do
    time_decay = clamp(remaining_minutes / window_minutes, 0.0, 1.0)

    # Decay toward 50% as time runs out
    adjusted_up = clamp(0.5 + (raw_up - 0.5) * time_decay, 0.0, 1.0)

    %{
      time_decay: time_decay,
      adjusted_up: adjusted_up,
      adjusted_down: 1.0 - adjusted_up
    }
  end

  def apply_time_awareness(_, _, _) do
    %{time_decay: 0.0, adjusted_up: 0.5, adjusted_down: 0.5}
  end

  # Private scoring helpers

  defp score_price_vwap(up, down, price, vwap)
       when is_number(price) and is_number(vwap) do
    cond do
      price > vwap -> {up + 2, down}
      price < vwap -> {up, down + 2}
      true -> {up, down}
    end
  end

  defp score_price_vwap(up, down, _, _), do: {up, down}

  defp score_vwap_slope(up, down, vwap_slope) when is_number(vwap_slope) do
    cond do
      vwap_slope > 0 -> {up + 2, down}
      vwap_slope < 0 -> {up, down + 2}
      true -> {up, down}
    end
  end

  defp score_vwap_slope(up, down, _), do: {up, down}

  defp score_rsi(up, down, rsi, rsi_slope)
       when is_number(rsi) and is_number(rsi_slope) do
    cond do
      rsi > 55 and rsi_slope > 0 -> {up + 2, down}
      rsi < 45 and rsi_slope < 0 -> {up, down + 2}
      true -> {up, down}
    end
  end

  defp score_rsi(up, down, _, _), do: {up, down}

  defp score_macd(up, down, %{hist: hist, hist_delta: hist_delta, macd: macd_line})
       when is_number(hist) and is_number(hist_delta) do
    # Histogram expansion scoring (+2)
    {up, down} =
      cond do
        hist > 0 and hist_delta > 0 -> {up + 2, down}
        hist < 0 and hist_delta < 0 -> {up, down + 2}
        true -> {up, down}
      end

    # MACD line bias (+1)
    if is_number(macd_line) do
      cond do
        macd_line > 0 -> {up + 1, down}
        macd_line < 0 -> {up, down + 1}
        true -> {up, down}
      end
    else
      {up, down}
    end
  end

  defp score_macd(up, down, _), do: {up, down}

  defp score_heiken_ashi(up, down, color, count)
       when is_binary(color) and is_integer(count) and count >= 2 do
    case color do
      "green" -> {up + 1, down}
      "red" -> {up, down + 1}
      _ -> {up, down}
    end
  end

  defp score_heiken_ashi(up, down, _, _), do: {up, down}

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
