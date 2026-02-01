defmodule PolymarketBot.Data.Binance do
  @moduledoc """
  Binance API client for fetching real-time price data.

  Provides functions to fetch klines (candlestick data) and
  current price from Binance's public REST API.
  """

  require Logger

  @default_base_url "https://api.binance.com"
  @default_symbol "BTCUSDT"

  @type candle :: %{
          open_time: integer(),
          open: float(),
          high: float(),
          low: float(),
          close: float(),
          volume: float(),
          close_time: integer()
        }

  @doc """
  Fetches klines (candlestick data) from Binance.

  ## Options

  - `:symbol` - Trading pair (default: "BTCUSDT")
  - `:interval` - Candle interval (default: "1m")
  - `:limit` - Number of candles (default: 100, max: 1000)
  - `:base_url` - API base URL (default: "https://api.binance.com")

  ## Returns

  `{:ok, [candle]}` or `{:error, reason}`

  ## Examples

      iex> PolymarketBot.Data.Binance.fetch_klines(interval: "15m", limit: 50)
      {:ok, [%{open: 95000.0, high: 95100.0, ...}, ...]}

  """
  @spec fetch_klines(keyword()) :: {:ok, [candle()]} | {:error, term()}
  def fetch_klines(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, get_config(:base_url, @default_base_url))
    symbol = Keyword.get(opts, :symbol, get_config(:default_symbol, @default_symbol))
    interval = Keyword.get(opts, :interval, "1m")
    limit = Keyword.get(opts, :limit, 100)

    url = "#{base_url}/api/v3/klines?symbol=#{symbol}&interval=#{interval}&limit=#{limit}"

    case http_get(url) do
      {:ok, body} ->
        candles = parse_klines(body)
        {:ok, candles}

      {:error, reason} ->
        Logger.error("[Binance] Failed to fetch klines: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches the last traded price for a symbol.

  ## Options

  - `:symbol` - Trading pair (default: "BTCUSDT")
  - `:base_url` - API base URL (default: "https://api.binance.com")

  ## Returns

  `{:ok, price}` or `{:error, reason}`

  ## Examples

      iex> PolymarketBot.Data.Binance.fetch_last_price()
      {:ok, 95234.56}

  """
  @spec fetch_last_price(keyword()) :: {:ok, float()} | {:error, term()}
  def fetch_last_price(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, get_config(:base_url, @default_base_url))
    symbol = Keyword.get(opts, :symbol, get_config(:default_symbol, @default_symbol))

    url = "#{base_url}/api/v3/ticker/price?symbol=#{symbol}"

    case http_get(url) do
      {:ok, %{"price" => price_str}} ->
        case Float.parse(price_str) do
          {price, _} -> {:ok, price}
          :error -> {:error, :invalid_price}
        end

      {:ok, _} ->
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("[Binance] Failed to fetch last price: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches the 24hr ticker statistics for a symbol.

  ## Options

  - `:symbol` - Trading pair (default: "BTCUSDT")
  - `:base_url` - API base URL (default: "https://api.binance.com")

  ## Returns

  `{:ok, stats}` or `{:error, reason}`
  """
  @spec fetch_24hr_stats(keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_24hr_stats(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, get_config(:base_url, @default_base_url))
    symbol = Keyword.get(opts, :symbol, get_config(:default_symbol, @default_symbol))

    url = "#{base_url}/api/v3/ticker/24hr?symbol=#{symbol}"

    case http_get(url) do
      {:ok, data} when is_map(data) ->
        stats = %{
          price_change: to_float(data["priceChange"]),
          price_change_percent: to_float(data["priceChangePercent"]),
          high_price: to_float(data["highPrice"]),
          low_price: to_float(data["lowPrice"]),
          volume: to_float(data["volume"]),
          quote_volume: to_float(data["quoteVolume"])
        }

        {:ok, stats}

      {:ok, _} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp http_get(url) do
    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 10_000}], []) do
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
        close_time: Enum.at(k, 6)
      }
    end)
  end

  defp parse_klines(_), do: []

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

  defp get_config(key, default) do
    Application.get_env(:polymarket_bot, :binance, [])
    |> Keyword.get(key, default)
  end
end
