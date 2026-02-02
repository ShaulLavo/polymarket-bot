defmodule PolymarketBot.Indicators.HeikenAshi do
  @moduledoc """
  Heiken Ashi (smoothed) candlestick indicator.

  Heiken Ashi candles smooth price action to make trends easier to identify.
  They use a modified formula that averages the open, high, low, and close.
  """

  @doc """
  Computes Heiken Ashi candles from regular OHLC candles.

  Each input candle should have :open, :high, :low, :close keys.
  Returns a list of Heiken Ashi candles with:
  - :open, :high, :low, :close - HA values
  - :is_green - true if close >= open (bullish)
  - :body - absolute difference between close and open

  ## Examples

      iex> candles = [%{open: 100, high: 105, low: 98, close: 103}]
      iex> [ha] = PolymarketBot.Indicators.HeikenAshi.compute_heiken_ashi(candles)
      iex> ha.is_green
      true

  """
  @spec compute_heiken_ashi([map()]) :: [map()]
  def compute_heiken_ashi(candles) when is_list(candles) and length(candles) == 0, do: []

  def compute_heiken_ashi(candles) when is_list(candles) do
    candles
    |> Enum.with_index()
    |> Enum.reduce([], fn {candle, _idx}, acc ->
      ha_close = (candle.open + candle.high + candle.low + candle.close) / 4

      ha_open =
        case acc do
          [] ->
            # First candle: use average of open and close
            (candle.open + candle.close) / 2

          [prev | _] ->
            # Subsequent candles: use average of previous HA open and close
            (prev.open + prev.close) / 2
        end

      ha_high = Enum.max([candle.high, ha_open, ha_close])
      ha_low = Enum.min([candle.low, ha_open, ha_close])

      ha_candle = %{
        open: ha_open,
        high: ha_high,
        low: ha_low,
        close: ha_close,
        is_green: ha_close >= ha_open,
        body: abs(ha_close - ha_open)
      }

      [ha_candle | acc]
    end)
    |> Enum.reverse()
  end

  def compute_heiken_ashi(_), do: []

  @doc """
  Counts consecutive candles of the same color from the end.

  Returns a map with:
  - :color - "green" or "red" (or nil if empty)
  - :count - number of consecutive candles of that color

  ## Examples

      iex> ha_candles = [
      ...>   %{is_green: true},
      ...>   %{is_green: true},
      ...>   %{is_green: false},
      ...>   %{is_green: false},
      ...>   %{is_green: false}
      ...> ]
      iex> PolymarketBot.Indicators.HeikenAshi.count_consecutive(ha_candles)
      %{color: "red", count: 3}

  """
  @spec count_consecutive([map()]) :: %{color: String.t() | nil, count: non_neg_integer()}
  def count_consecutive(ha_candles) when is_list(ha_candles) and length(ha_candles) == 0 do
    %{color: nil, count: 0}
  end

  def count_consecutive(ha_candles) when is_list(ha_candles) do
    last = List.last(ha_candles)
    target_green = last.is_green
    target_color = if target_green, do: "green", else: "red"

    count =
      ha_candles
      |> Enum.reverse()
      |> Enum.take_while(fn candle -> candle.is_green == target_green end)
      |> length()

    %{color: target_color, count: count}
  end

  def count_consecutive(_), do: %{color: nil, count: 0}
end
