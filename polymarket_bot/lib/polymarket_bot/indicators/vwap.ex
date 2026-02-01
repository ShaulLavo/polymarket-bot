defmodule PolymarketBot.Indicators.VWAP do
  @moduledoc """
  Volume-Weighted Average Price (VWAP) indicator.

  VWAP is calculated as the cumulative sum of (typical price * volume)
  divided by cumulative volume for a trading session.
  """

  @doc """
  Computes the session VWAP for a list of candles.

  Each candle should have :high, :low, :close, and :volume keys.
  Returns nil if candles is empty or total volume is 0.

  ## Examples

      iex> candles = [%{high: 100, low: 98, close: 99, volume: 1000}]
      iex> PolymarketBot.Indicators.VWAP.compute_session_vwap(candles)
      99.0

  """
  @spec compute_session_vwap([map()]) :: float() | nil
  def compute_session_vwap(candles) when is_list(candles) and length(candles) == 0, do: nil

  def compute_session_vwap(candles) when is_list(candles) do
    {pv_sum, v_sum} =
      Enum.reduce(candles, {0.0, 0.0}, fn c, {pv, v} ->
        typical_price = (c.high + c.low + c.close) / 3
        {pv + typical_price * c.volume, v + c.volume}
      end)

    if v_sum == 0, do: nil, else: pv_sum / v_sum
  end

  def compute_session_vwap(_), do: nil

  @doc """
  Computes a running VWAP series for each point in the candle list.

  Returns a list of VWAP values where each element is the VWAP
  from the start of the session up to that candle.

  ## Examples

      iex> candles = [
      ...>   %{high: 100, low: 98, close: 99, volume: 1000},
      ...>   %{high: 102, low: 100, close: 101, volume: 1500}
      ...> ]
      iex> PolymarketBot.Indicators.VWAP.compute_vwap_series(candles)
      [99.0, 100.2]

  """
  @spec compute_vwap_series([map()]) :: [float() | nil]
  def compute_vwap_series(candles) when is_list(candles) do
    candles
    |> Enum.with_index(1)
    |> Enum.map(fn {_candle, idx} ->
      compute_session_vwap(Enum.take(candles, idx))
    end)
  end

  def compute_vwap_series(_), do: []

  @doc """
  Computes the slope of a series over the last N points.

  The slope is calculated as (last - first) / (points - 1).
  Returns nil if there aren't enough points.

  ## Examples

      iex> PolymarketBot.Indicators.VWAP.compute_slope([1.0, 2.0, 3.0], 3)
      1.0

  """
  @spec compute_slope([number()], pos_integer()) :: float() | nil
  def compute_slope(values, points)
      when is_list(values) and is_integer(points) and points > 1 do
    if length(values) < points do
      nil
    else
      slice = Enum.take(values, -points)
      first = List.first(slice)
      last = List.last(slice)
      (last - first) / (points - 1)
    end
  end

  def compute_slope(_, _), do: nil

  @doc """
  Counts the number of times price crosses the VWAP series.

  A cross occurs when price moves from above to below or below to above VWAP.
  Requires parallel lists of prices and VWAP values.

  ## Examples

      iex> prices = [99.0, 101.0, 99.0, 101.0]
      iex> vwaps = [100.0, 100.0, 100.0, 100.0]
      iex> PolymarketBot.Indicators.VWAP.count_crosses(prices, vwaps)
      3

  """
  @spec count_crosses([number()], [number()]) :: non_neg_integer()
  def count_crosses(prices, vwaps)
      when is_list(prices) and is_list(vwaps) and length(prices) == length(vwaps) do
    prices
    |> Enum.zip(vwaps)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [{p1, v1}, {p2, v2}] ->
      above_before = p1 > v1
      above_after = p2 > v2
      above_before != above_after
    end)
  end

  def count_crosses(_, _), do: 0
end
