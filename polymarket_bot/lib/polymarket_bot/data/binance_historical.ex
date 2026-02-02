defmodule PolymarketBot.Data.BinanceHistorical do
  @moduledoc """
  Historical data fetcher for Binance klines.

  Provides functions to fetch historical candlestick data from Binance
  for backtesting regime detection and strategy evaluation.
  """

  require Logger

  @default_base_url "https://api.binance.com"
  @default_symbol "BTCUSDT"
  @max_limit 1000

  @type candle :: %{
          open_time: integer(),
          open: float(),
          high: float(),
          low: float(),
          close: float(),
          volume: float(),
          close_time: integer(),
          quote_volume: float(),
          trades: integer()
        }

  @doc """
  Fetches historical klines for a specific time range.

  ## Options

  - `:symbol` - Trading pair (default: "BTCUSDT")
  - `:interval` - Candle interval ("1m", "5m", "15m", "1h", "4h", "1d")
  - `:start_time` - Start time as DateTime or Unix ms
  - `:end_time` - End time as DateTime or Unix ms (default: now)
  - `:limit` - Max candles per request (default: 1000)
  - `:base_url` - API base URL

  ## Returns

  `{:ok, [candle]}` or `{:error, reason}`

  ## Examples

      iex> start = DateTime.add(DateTime.utc_now(), -24, :hour)
      iex> PolymarketBot.Data.BinanceHistorical.fetch_historical(
      ...>   interval: "15m",
      ...>   start_time: start
      ...> )
      {:ok, [%{open: 95000.0, ...}, ...]}

  """
  @spec fetch_historical(keyword()) :: {:ok, [candle()]} | {:error, term()}
  def fetch_historical(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, get_config(:base_url, @default_base_url))
    symbol = Keyword.get(opts, :symbol, get_config(:default_symbol, @default_symbol))
    interval = Keyword.get(opts, :interval, "1m")
    limit = min(Keyword.get(opts, :limit, @max_limit), @max_limit)
    start_time = opts |> Keyword.get(:start_time) |> to_unix_ms()
    end_time = opts |> Keyword.get(:end_time) |> to_unix_ms()

    params =
      [
        {"symbol", symbol},
        {"interval", interval},
        {"limit", Integer.to_string(limit)}
      ]
      |> maybe_add_param("startTime", start_time)
      |> maybe_add_param("endTime", end_time)

    query = URI.encode_query(params)
    url = "#{base_url}/api/v3/klines?#{query}"

    case http_get(url) do
      {:ok, data} when is_list(data) ->
        candles = parse_klines(data)
        {:ok, candles}

      {:ok, _} ->
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("[BinanceHistorical] Failed to fetch historical data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches all historical klines between two timestamps.

  Automatically paginates through multiple requests if needed.
  Rate-limits requests to avoid hitting API limits.

  ## Options

  - `:symbol` - Trading pair (default: "BTCUSDT")
  - `:interval` - Candle interval
  - `:start_time` - Start time as DateTime or Unix ms (required)
  - `:end_time` - End time as DateTime or Unix ms (default: now)
  - `:rate_limit_ms` - Delay between requests (default: 100ms)

  ## Returns

  `{:ok, [candle]}` or `{:error, reason}`

  ## Examples

      iex> start = ~U[2024-01-01 00:00:00Z]
      iex> end_time = ~U[2024-01-02 00:00:00Z]
      iex> PolymarketBot.Data.BinanceHistorical.fetch_all_historical(
      ...>   interval: "1m",
      ...>   start_time: start,
      ...>   end_time: end_time
      ...> )
      {:ok, [%{open: 42000.0, ...}, ...]}

  """
  @spec fetch_all_historical(keyword()) :: {:ok, [candle()]} | {:error, term()}
  def fetch_all_historical(opts \\ []) do
    start_time = opts |> Keyword.get(:start_time) |> to_unix_ms()
    end_time = opts |> Keyword.get(:end_time) |> to_unix_ms() || System.system_time(:millisecond)
    rate_limit_ms = Keyword.get(opts, :rate_limit_ms, 100)

    if is_nil(start_time) do
      {:error, :start_time_required}
    else
      fetch_all_pages(opts, start_time, end_time, rate_limit_ms, [])
    end
  end

  @doc """
  Fetches the last N days of historical data.

  Convenience function for common backtesting scenarios.

  ## Options

  - `:symbol` - Trading pair (default: "BTCUSDT")
  - `:interval` - Candle interval (default: "15m")
  - `:days` - Number of days to fetch (default: 7)

  ## Returns

  `{:ok, [candle]}` or `{:error, reason}`

  ## Examples

      iex> PolymarketBot.Data.BinanceHistorical.fetch_last_n_days(days: 3, interval: "15m")
      {:ok, [%{open: 95000.0, ...}, ...]}

  """
  @spec fetch_last_n_days(keyword()) :: {:ok, [candle()]} | {:error, term()}
  def fetch_last_n_days(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    start_time = DateTime.add(DateTime.utc_now(), -days, :day)
    end_time = DateTime.utc_now()

    opts
    |> Keyword.put(:start_time, start_time)
    |> Keyword.put(:end_time, end_time)
    |> fetch_all_historical()
  end

  @doc """
  Groups candles by 15-minute windows for regime analysis.

  Takes a list of 1-minute candles and aggregates them into
  15-minute windows aligned to the hour (0, 15, 30, 45).

  ## Returns

  List of maps with :window_start and :candles keys.
  """
  @spec group_into_windows([candle()], pos_integer()) :: [map()]
  def group_into_windows(candles, window_minutes \\ 15) do
    window_ms = window_minutes * 60 * 1000

    candles
    |> Enum.group_by(fn c ->
      # Align to window boundaries
      div(c.open_time, window_ms) * window_ms
    end)
    |> Enum.sort_by(fn {window_start, _} -> window_start end)
    |> Enum.map(fn {window_start, window_candles} ->
      %{
        window_start: window_start,
        window_start_dt: DateTime.from_unix!(window_start, :millisecond),
        candles: Enum.sort_by(window_candles, & &1.open_time)
      }
    end)
  end

  @doc """
  Aggregates 1-minute candles into a single OHLCV candle for a window.

  Used to convert grouped 1m candles into a single 15m candle.
  """
  @spec aggregate_candles([candle()]) :: candle() | nil
  def aggregate_candles([]), do: nil

  def aggregate_candles(candles) do
    sorted = Enum.sort_by(candles, & &1.open_time)
    first = List.first(sorted)
    last = List.last(sorted)

    %{
      open_time: first.open_time,
      open: first.open,
      high: Enum.max_by(sorted, & &1.high).high,
      low: Enum.min_by(sorted, & &1.low).low,
      close: last.close,
      volume: Enum.reduce(sorted, 0.0, &(&1.volume + &2)),
      close_time: last.close_time,
      quote_volume: Enum.reduce(sorted, 0.0, &((&1[:quote_volume] || 0) + &2)),
      trades: Enum.reduce(sorted, 0, &((&1[:trades] || 0) + &2))
    }
  end

  # Private functions

  defp fetch_all_pages(_opts, current_start, end_time, _rate_limit_ms, acc)
       when current_start >= end_time do
    {:ok, Enum.reverse(acc) |> List.flatten()}
  end

  defp fetch_all_pages(opts, current_start, end_time, rate_limit_ms, acc) do
    case fetch_historical(Keyword.put(opts, :start_time, current_start)) do
      {:ok, []} ->
        {:ok, Enum.reverse(acc) |> List.flatten()}

      {:ok, candles} ->
        last_candle = List.last(candles)
        next_start = last_candle.close_time + 1

        if next_start >= end_time or length(candles) < @max_limit do
          # Filter candles that are beyond end_time
          filtered =
            Enum.filter(candles, fn c ->
              c.open_time < end_time
            end)

          {:ok, Enum.reverse([filtered | acc]) |> List.flatten()}
        else
          # Rate limit to avoid hitting API limits
          Process.sleep(rate_limit_ms)
          fetch_all_pages(opts, next_start, end_time, rate_limit_ms, [candles | acc])
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_get(url) do
    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 30_000}], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        Jason.decode(to_string(body))

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, {:http_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_klines(data) when is_list(data) do
    Enum.map(data, fn k ->
      %{
        open_time: Enum.at(k, 0),
        open: to_float(Enum.at(k, 1)),
        high: to_float(Enum.at(k, 2)),
        low: to_float(Enum.at(k, 3)),
        close: to_float(Enum.at(k, 4)),
        volume: to_float(Enum.at(k, 5)),
        close_time: Enum.at(k, 6),
        quote_volume: to_float(Enum.at(k, 7)),
        trades: Enum.at(k, 8)
      }
    end)
  end

  defp parse_klines(_), do: []

  defp to_unix_ms(nil), do: nil
  defp to_unix_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)
  defp to_unix_ms(ms) when is_integer(ms), do: ms
  defp to_unix_ms(_), do: nil

  defp to_float(nil), do: nil

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(_), do: nil

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: params ++ [{key, Integer.to_string(value)}]

  defp get_config(key, default) do
    Application.get_env(:polymarket_bot, :binance, [])
    |> Keyword.get(key, default)
  end
end
