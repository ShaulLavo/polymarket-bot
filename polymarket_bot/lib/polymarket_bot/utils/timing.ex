defmodule PolymarketBot.Utils.Timing do
  @moduledoc """
  Timing utilities for 15-minute window calculations.

  Provides functions to determine the current position within
  a trading window and calculate time remaining.
  """

  @doc """
  Gets timing information for the current candle window.

  ## Parameters

  - `window_minutes` - Window duration in minutes (default: 15)
  - `now` - Current time as DateTime (default: now)

  ## Returns

  Map with:
  - `:start_ms` - Window start time in Unix milliseconds
  - `:end_ms` - Window end time in Unix milliseconds
  - `:start_dt` - Window start as DateTime
  - `:end_dt` - Window end as DateTime
  - `:elapsed_ms` - Milliseconds elapsed since window start
  - `:remaining_ms` - Milliseconds until window end
  - `:elapsed_minutes` - Minutes elapsed since window start
  - `:remaining_minutes` - Minutes until window end
  - `:progress` - Progress through window (0.0 to 1.0)

  ## Examples

      iex> timing = PolymarketBot.Utils.Timing.get_window_timing(15)
      iex> timing.remaining_minutes <= 15
      true

  """
  @spec get_window_timing(pos_integer(), DateTime.t()) :: map()
  def get_window_timing(window_minutes \\ 15, now \\ DateTime.utc_now()) do
    now_ms = DateTime.to_unix(now, :millisecond)
    window_ms = window_minutes * 60 * 1000

    start_ms = div(now_ms, window_ms) * window_ms
    end_ms = start_ms + window_ms
    elapsed_ms = now_ms - start_ms
    remaining_ms = end_ms - now_ms

    %{
      start_ms: start_ms,
      end_ms: end_ms,
      start_dt: DateTime.from_unix!(start_ms, :millisecond) |> DateTime.truncate(:second),
      end_dt: DateTime.from_unix!(end_ms, :millisecond) |> DateTime.truncate(:second),
      elapsed_ms: elapsed_ms,
      remaining_ms: remaining_ms,
      elapsed_minutes: elapsed_ms / 60_000,
      remaining_minutes: remaining_ms / 60_000,
      progress: elapsed_ms / window_ms
    }
  end

  @doc """
  Determines the trading phase based on remaining time.

  ## Phases

  - `:early` - More than 10 minutes remaining
  - `:mid` - Between 5 and 10 minutes remaining
  - `:late` - Less than 5 minutes remaining

  ## Examples

      iex> PolymarketBot.Utils.Timing.get_phase(12.0)
      :early
      iex> PolymarketBot.Utils.Timing.get_phase(7.5)
      :mid
      iex> PolymarketBot.Utils.Timing.get_phase(2.0)
      :late

  """
  @spec get_phase(number()) :: :early | :mid | :late
  def get_phase(remaining_minutes) when is_number(remaining_minutes) do
    cond do
      remaining_minutes > 10 -> :early
      remaining_minutes > 5 -> :mid
      true -> :late
    end
  end

  @doc """
  Checks if we're in a suitable time window for trading.

  Returns false if we're in the last minute (too close to expiry)
  or first minute (waiting for price data).

  ## Examples

      iex> PolymarketBot.Utils.Timing.tradeable_window?(14.0)
      true
      iex> PolymarketBot.Utils.Timing.tradeable_window?(0.5)
      false

  """
  @spec tradeable_window?(number()) :: boolean()
  def tradeable_window?(remaining_minutes) when is_number(remaining_minutes) do
    # Avoid first minute (no data) and last minute (too risky)
    remaining_minutes >= 1.0 and remaining_minutes <= 14.0
  end

  @doc """
  Calculates the next window start time.

  ## Examples

      iex> now = ~U[2024-01-15 12:07:30Z]
      iex> PolymarketBot.Utils.Timing.next_window_start(15, now)
      ~U[2024-01-15 12:15:00Z]

  """
  @spec next_window_start(pos_integer(), DateTime.t()) :: DateTime.t()
  def next_window_start(window_minutes \\ 15, now \\ DateTime.utc_now()) do
    timing = get_window_timing(window_minutes, now)
    timing.end_dt
  end

  @doc """
  Calculates milliseconds until the next window starts.

  ## Examples

      iex> ms = PolymarketBot.Utils.Timing.ms_until_next_window(15)
      iex> ms >= 0 and ms <= 15 * 60 * 1000
      true

  """
  @spec ms_until_next_window(pos_integer(), DateTime.t()) :: non_neg_integer()
  def ms_until_next_window(window_minutes \\ 15, now \\ DateTime.utc_now()) do
    timing = get_window_timing(window_minutes, now)
    timing.remaining_ms
  end

  @doc """
  Formats remaining time as a human-readable string.

  ## Examples

      iex> PolymarketBot.Utils.Timing.format_remaining(7.5)
      "7m 30s"
      iex> PolymarketBot.Utils.Timing.format_remaining(0.5)
      "0m 30s"

  """
  @spec format_remaining(number()) :: String.t()
  def format_remaining(remaining_minutes) when is_number(remaining_minutes) do
    total_seconds = trunc(remaining_minutes * 60)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}m #{seconds}s"
  end

  @doc """
  Aligns a timestamp to the start of its window.

  ## Examples

      iex> ts = ~U[2024-01-15 12:07:30Z]
      iex> PolymarketBot.Utils.Timing.align_to_window(ts, 15)
      ~U[2024-01-15 12:00:00Z]

  """
  @spec align_to_window(DateTime.t(), pos_integer()) :: DateTime.t()
  def align_to_window(timestamp, window_minutes \\ 15) do
    ts_ms = DateTime.to_unix(timestamp, :millisecond)
    window_ms = window_minutes * 60 * 1000
    aligned_ms = div(ts_ms, window_ms) * window_ms
    DateTime.from_unix!(aligned_ms, :millisecond) |> DateTime.truncate(:second)
  end
end
