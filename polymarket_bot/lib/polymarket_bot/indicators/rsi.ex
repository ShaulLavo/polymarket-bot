defmodule PolymarketBot.Indicators.RSI do
  @moduledoc """
  Relative Strength Index (RSI) indicator.

  RSI measures the speed and magnitude of price movements,
  oscillating between 0 and 100.
  """

  @doc """
  Computes the RSI value for a list of closing prices.

  Uses Wilder's smoothing method. Returns nil if there aren't enough prices.
  RSI = 100 - (100 / (1 + RS)) where RS = avg gain / avg loss

  ## Examples

      iex> closes = [44, 44.34, 44.09, 43.61, 44.33, 44.83, 45.10,
      ...>           45.42, 45.84, 46.08, 45.89, 46.03, 45.61, 46.28, 46.28]
      iex> PolymarketBot.Indicators.RSI.compute_rsi(closes, 14)
      70.46...

  """
  @spec compute_rsi([number()], pos_integer()) :: float() | nil
  def compute_rsi(closes, period)
      when is_list(closes) and is_integer(period) and period > 0 do
    if length(closes) < period + 1 do
      nil
    else
      # Take the last (period + 1) prices for calculation
      recent = Enum.take(closes, -(period + 1))

      {gains, losses} =
        recent
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce({0.0, 0.0}, fn [prev, cur], {g, l} ->
          diff = cur - prev

          if diff > 0 do
            {g + diff, l}
          else
            {g, l + abs(diff)}
          end
        end)

      avg_gain = gains / period
      avg_loss = losses / period

      if avg_loss == 0 do
        100.0
      else
        rs = avg_gain / avg_loss
        rsi = 100.0 - 100.0 / (1.0 + rs)
        clamp(rsi, 0.0, 100.0)
      end
    end
  end

  def compute_rsi(_, _), do: nil

  @doc """
  Computes RSI for each point in the series (running RSI).

  Returns a list where each element is the RSI computed up to that point.
  Early elements will be nil until there's enough data.

  ## Examples

      iex> closes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
      iex> series = PolymarketBot.Indicators.RSI.compute_rsi_series(closes, 5)
      iex> length(series)
      15

  """
  @spec compute_rsi_series([number()], pos_integer()) :: [float() | nil]
  def compute_rsi_series(closes, period)
      when is_list(closes) and is_integer(period) and period > 0 do
    closes
    |> Enum.with_index(1)
    |> Enum.map(fn {_close, idx} ->
      compute_rsi(Enum.take(closes, idx), period)
    end)
  end

  def compute_rsi_series(_, _), do: []

  @doc """
  Computes the Simple Moving Average (SMA) of the last N values.

  Returns nil if there aren't enough values.

  ## Examples

      iex> PolymarketBot.Indicators.RSI.sma([1, 2, 3, 4, 5], 3)
      4.0

  """
  @spec sma([number()], pos_integer()) :: float() | nil
  def sma(values, period) when is_list(values) and is_integer(period) and period > 0 do
    if length(values) < period do
      nil
    else
      slice = Enum.take(values, -period)
      Enum.sum(slice) / period
    end
  end

  def sma(_, _), do: nil

  @doc """
  Computes the slope of the last N values.

  Slope is (last - first) / (points - 1).
  Returns nil if there aren't enough values.

  ## Examples

      iex> PolymarketBot.Indicators.RSI.slope_last([1, 2, 3, 4, 5], 3)
      2.0

  """
  @spec slope_last([number()], pos_integer()) :: float() | nil
  def slope_last(values, points)
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

  def slope_last(_, _), do: nil

  # Private helpers

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
