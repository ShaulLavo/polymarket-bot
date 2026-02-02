defmodule PolymarketBot.Indicators.MACD do
  @moduledoc """
  Moving Average Convergence Divergence (MACD) indicator.

  MACD shows the relationship between two moving averages of prices.
  It consists of the MACD line, signal line, and histogram.
  """

  @doc """
  Computes the Exponential Moving Average (EMA) of values.

  Uses the standard EMA formula: EMA_t = value_t * k + EMA_{t-1} * (1 - k)
  where k = 2 / (period + 1)

  Returns nil if there aren't enough values.

  ## Examples

      iex> PolymarketBot.Indicators.MACD.ema([1, 2, 3, 4, 5], 3)
      4.0

  """
  @spec ema([number()], pos_integer()) :: float() | nil
  def ema(values, period) when is_list(values) and is_integer(period) and period > 0 do
    if length(values) < period do
      nil
    else
      k = 2.0 / (period + 1)
      [first | rest] = values

      Enum.reduce(rest, first * 1.0, fn value, prev_ema ->
        value * k + prev_ema * (1 - k)
      end)
    end
  end

  def ema(_, _), do: nil

  @doc """
  Computes the MACD indicator for a list of closing prices.

  Returns a map with:
  - `:macd` - The MACD line (fast EMA - slow EMA)
  - `:signal` - The signal line (EMA of MACD line)
  - `:hist` - The histogram (MACD - signal)
  - `:hist_delta` - Change in histogram from previous bar

  Standard parameters are fast=12, slow=26, signal=9.
  Returns nil if there isn't enough data.

  ## Examples

      iex> closes = Enum.to_list(1..50)
      iex> result = PolymarketBot.Indicators.MACD.compute_macd(closes, 12, 26, 9)
      iex> is_map(result)
      true

  """
  @spec compute_macd([number()], pos_integer(), pos_integer(), pos_integer()) :: map() | nil
  def compute_macd(closes, fast, slow, signal)
      when is_list(closes) and is_integer(fast) and is_integer(slow) and is_integer(signal) do
    min_required = slow + signal

    if length(closes) < min_required do
      nil
    else
      fast_ema = ema(closes, fast)
      slow_ema = ema(closes, slow)

      if is_nil(fast_ema) or is_nil(slow_ema) do
        nil
      else
        macd_line = fast_ema - slow_ema

        # Build the MACD series for signal line calculation
        macd_series = build_macd_series(closes, fast, slow)

        signal_line = ema(macd_series, signal)

        if is_nil(signal_line) do
          nil
        else
          hist = macd_line - signal_line

          # Calculate previous histogram for delta
          prev_hist = calculate_prev_hist(closes, fast, slow, signal)

          hist_delta =
            if is_nil(prev_hist) do
              nil
            else
              hist - prev_hist
            end

          %{
            macd: macd_line,
            signal: signal_line,
            hist: hist,
            hist_delta: hist_delta
          }
        end
      end
    end
  end

  def compute_macd(_, _, _, _), do: nil

  # Build a series of MACD values (fast EMA - slow EMA) for each point
  defp build_macd_series(closes, fast, slow) do
    closes
    |> Enum.with_index(1)
    |> Enum.map(fn {_close, idx} ->
      sub = Enum.take(closes, idx)
      f = ema(sub, fast)
      s = ema(sub, slow)

      if is_nil(f) or is_nil(s) do
        nil
      else
        f - s
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Calculate the histogram from the previous bar
  defp calculate_prev_hist(closes, fast, slow, signal) do
    if length(closes) < slow + signal + 1 do
      nil
    else
      prev_closes = Enum.take(closes, length(closes) - 1)
      prev_macd_series = build_macd_series(prev_closes, fast, slow)

      if length(prev_macd_series) < signal do
        nil
      else
        prev_fast_ema = ema(prev_closes, fast)
        prev_slow_ema = ema(prev_closes, slow)
        prev_signal = ema(prev_macd_series, signal)

        if is_nil(prev_fast_ema) or is_nil(prev_slow_ema) or is_nil(prev_signal) do
          nil
        else
          prev_macd = prev_fast_ema - prev_slow_ema
          prev_macd - prev_signal
        end
      end
    end
  end
end
