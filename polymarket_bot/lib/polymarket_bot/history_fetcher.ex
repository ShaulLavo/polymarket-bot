defmodule PolymarketBot.HistoryFetcher do
  @moduledoc """
  Fetches historical data from Polymarket APIs for BTC 15-min markets.

  Provides functions to:
  - Fetch historical price data via CLOB /prices-history
  - Fetch market activity via Gamma API
  - Discover past BTC 15-min market epochs
  - Store data in JSON format compatible with data_collector snapshots

  ## Rate Limiting

  Polymarket allows ~1000 requests/hour. This module implements:
  - Configurable delay between requests (default 100ms = 36,000/hr theoretical max)
  - Exponential backoff on rate limit errors
  - Batch fetching with progress reporting

  ## Usage

      # Fetch last 24 hours of price history for a token
      {:ok, history} = HistoryFetcher.fetch_price_history(token_id, interval: "1d")

      # Fetch historical BTC 15-min markets
      {:ok, markets} = HistoryFetcher.fetch_btc_15m_history(hours: 24)

      # Save fetched data to disk
      HistoryFetcher.save_history(data, "btc_15m_prices")
  """

  require Logger

  @gamma_url "https://gamma-api.polymarket.com"
  @clob_url "https://clob.polymarket.com"
  @user_agent "PolymarketBot/1.0"

  # Rate limiting defaults
  @default_rate_limit_ms 100
  @backoff_base_ms 1000

  # Pagination
  @max_activity_per_request 100

  # Data storage path
  @data_dir "priv/data/btc_15_min/history"

  # ============================================================================
  # PUBLIC API - Price History
  # ============================================================================

  @doc """
  Fetches historical price data for a token.

  Uses the CLOB /prices-history endpoint.

  ## Options

  - `:interval` - Time range: "1d", "1w", "1m", "max" (default: "1d")
  - `:fidelity` - Data point frequency in seconds (default: 60)

  ## Returns

  `{:ok, [%{timestamp: unix_ts, price: float}]}` or `{:error, reason}`

  ## Example

      {:ok, history} = HistoryFetcher.fetch_price_history(token_id, interval: "1w", fidelity: 300)
  """
  @spec fetch_price_history(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def fetch_price_history(token_id, opts \\ []) do
    interval = Keyword.get(opts, :interval, "1d")
    fidelity = Keyword.get(opts, :fidelity, 60)

    params = %{
      market: token_id,
      interval: interval,
      fidelity: fidelity
    }

    case request(:get, "#{@clob_url}/prices-history", params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_price_history(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches historical price data for multiple tokens in parallel with rate limiting.

  ## Options

  - `:interval` - Time range (default: "1d")
  - `:fidelity` - Frequency in seconds (default: 60)
  - `:rate_limit_ms` - Delay between requests (default: 100)
  - `:on_progress` - Callback function `fn(current, total) -> :ok end`

  ## Returns

  `{:ok, %{token_id => history}}` or `{:error, reason}`
  """
  @spec fetch_price_history_batch([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_price_history_batch(token_ids, opts \\ []) do
    rate_limit_ms = Keyword.get(opts, :rate_limit_ms, @default_rate_limit_ms)
    on_progress = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)
    total = length(token_ids)

    results =
      token_ids
      |> Enum.with_index(1)
      |> Enum.reduce_while(%{}, fn {token_id, idx}, acc ->
        on_progress.(idx, total)

        case fetch_price_history(token_id, opts) do
          {:ok, history} ->
            Process.sleep(rate_limit_ms)
            {:cont, Map.put(acc, token_id, history)}

          {:error, {429, _}} ->
            Logger.warning("Rate limited, backing off...")
            Process.sleep(@backoff_base_ms * 2)
            # Retry once
            case fetch_price_history(token_id, opts) do
              {:ok, history} -> {:cont, Map.put(acc, token_id, history)}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:error, reason} ->
            Logger.error("Failed to fetch history for #{token_id}: #{inspect(reason)}")
            {:cont, Map.put(acc, token_id, {:error, reason})}
        end
      end)

    case results do
      {:error, _} = err -> err
      map -> {:ok, map}
    end
  end

  # ============================================================================
  # PUBLIC API - BTC 15-min Markets
  # ============================================================================

  @doc """
  Discovers historical BTC 15-min market epochs.

  Calculates epoch timestamps going back the specified number of hours
  and attempts to fetch market data for each epoch.

  ## Options

  - `:hours` - Number of hours to look back (default: 24)
  - `:rate_limit_ms` - Delay between requests (default: 100)
  - `:on_progress` - Progress callback

  ## Returns

  `{:ok, [market_data]}` - List of markets that were found
  """
  @spec fetch_btc_15m_history(keyword()) :: {:ok, list(map())} | {:error, term()}
  def fetch_btc_15m_history(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    rate_limit_ms = Keyword.get(opts, :rate_limit_ms, @default_rate_limit_ms)
    on_progress = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)

    # Calculate epochs (15-minute intervals)
    now = System.os_time(:second)
    current_epoch = div(now, 900) * 900
    epochs_count = div(hours * 60, 15)

    epochs =
      Enum.map(0..(epochs_count - 1), fn i ->
        current_epoch - i * 900
      end)

    total = length(epochs)
    Logger.info("Fetching #{total} BTC 15-min epochs (last #{hours} hours)")

    results =
      epochs
      |> Enum.with_index(1)
      |> Enum.reduce([], fn {epoch, idx}, acc ->
        on_progress.(idx, total)

        case fetch_btc_15m_epoch(epoch) do
          {:ok, event} ->
            Process.sleep(rate_limit_ms)
            [event | acc]

          {:error, {404, _}} ->
            # Market doesn't exist for this epoch - normal
            Process.sleep(div(rate_limit_ms, 2))
            acc

          {:error, {429, _}} ->
            Logger.warning("Rate limited at epoch #{epoch}, backing off...")
            Process.sleep(@backoff_base_ms * 2)
            # Retry
            case fetch_btc_15m_epoch(epoch) do
              {:ok, event} -> [event | acc]
              _ -> acc
            end

          {:error, reason} ->
            Logger.debug("Failed to fetch epoch #{epoch}: #{inspect(reason)}")
            acc
        end
      end)

    Logger.info("Found #{length(results)} BTC 15-min markets")
    {:ok, Enum.reverse(results)}
  end

  @doc """
  Fetches a specific BTC 15-min event by epoch timestamp.

  ## Example

      epoch = 1704067200  # Unix timestamp aligned to 15-min boundary
      {:ok, event} = HistoryFetcher.fetch_btc_15m_epoch(epoch)
  """
  @spec fetch_btc_15m_epoch(integer()) :: {:ok, map()} | {:error, term()}
  def fetch_btc_15m_epoch(epoch) do
    url = "#{@gamma_url}/events/slug/btc-updown-15m-#{epoch}"

    case request(:get, url, headers: [{"user-agent", @user_agent}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches BTC 15-min history and extracts price snapshots.

  Returns data in the same format as data_collector snapshots for consistency.

  ## Options

  - `:hours` - Hours to look back (default: 24)
  - `:rate_limit_ms` - Delay between requests (default: 100)

  ## Returns

  `{:ok, [snapshot]}` where each snapshot matches the PriceSnapshot format
  """
  @spec fetch_btc_15m_snapshots(keyword()) :: {:ok, list(map())}
  def fetch_btc_15m_snapshots(opts \\ []) do
    {:ok, events} = fetch_btc_15m_history(opts)

    snapshots =
      events
      |> Enum.flat_map(&extract_snapshots_from_event/1)
      |> Enum.sort_by(& &1.timestamp, DateTime)

    {:ok, snapshots}
  end

  # ============================================================================
  # PUBLIC API - Market Activity
  # ============================================================================

  @doc """
  Fetches recent activity for a market from Gamma API.

  ## Options

  - `:limit` - Max results per request (default: 100)
  - `:offset` - Pagination offset (default: 0)

  Note: This endpoint may have limited historical depth.
  """
  @spec fetch_market_activity(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def fetch_market_activity(market_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @max_activity_per_request)
    offset = Keyword.get(opts, :offset, 0)

    params = %{
      market: market_id,
      limit: limit,
      offset: offset
    }

    case request(:get, "#{@gamma_url}/activity", params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches all available activity for a market with pagination.

  ## Options

  - `:max_pages` - Maximum pages to fetch (default: 10)
  - `:rate_limit_ms` - Delay between requests (default: 100)
  """
  @spec fetch_all_market_activity(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def fetch_all_market_activity(market_id, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, 10)
    rate_limit_ms = Keyword.get(opts, :rate_limit_ms, @default_rate_limit_ms)

    fetch_activity_pages(market_id, 0, max_pages, rate_limit_ms, [])
  end

  # ============================================================================
  # PUBLIC API - Data Storage
  # ============================================================================

  @doc """
  Saves historical data to a JSON file.

  Data is stored in `priv/data/btc_15_min/history/` with timestamps.

  ## Example

      HistoryFetcher.save_history(snapshots, "btc_15m_snapshots")
      # Creates: priv/data/btc_15_min/history/btc_15m_snapshots_2024-01-15T10:30:00Z.json
  """
  @spec save_history(term(), String.t()) :: :ok | {:error, term()}
  def save_history(data, name) do
    ensure_data_dir()

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    filename = "#{name}_#{timestamp}.json"
    path = Path.join([@data_dir, filename])

    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write(path, json)
        Logger.info("Saved history to #{path}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Loads historical data from a JSON file.

  ## Example

      {:ok, data} = HistoryFetcher.load_history("btc_15m_snapshots_2024-01-15T10:30:00Z.json")
  """
  @spec load_history(String.t()) :: {:ok, term()} | {:error, term()}
  def load_history(filename) do
    path = Path.join([@data_dir, filename])

    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all saved history files.
  """
  @spec list_history_files() :: {:ok, [String.t()]} | {:error, term()}
  def list_history_files do
    ensure_data_dir()
    path = Path.join([@data_dir, "*.json"])

    files =
      Path.wildcard(path)
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

    {:ok, files}
  end

  @doc """
  Convenience function to fetch and save BTC 15-min history.

  ## Options

  - `:hours` - Hours to look back (default: 24)
  - `:save` - Whether to save to disk (default: true)
  """
  @spec collect_btc_15m_history(keyword()) :: {:ok, list(map())}
  def collect_btc_15m_history(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    should_save = Keyword.get(opts, :save, true)

    Logger.info("Collecting BTC 15-min history for last #{hours} hours...")

    {:ok, snapshots} = fetch_btc_15m_snapshots(opts)

    if should_save and length(snapshots) > 0 do
      save_history(snapshots, "btc_15m_snapshots")
    end

    Logger.info("Collected #{length(snapshots)} snapshots")
    {:ok, snapshots}
  end

  # ============================================================================
  # PRIVATE - HTTP Helpers
  # ============================================================================

  defp request(method, url, opts) do
    Req.request([method: method, url: url] ++ opts)
  end

  # ============================================================================
  # PRIVATE - Parsing
  # ============================================================================

  defp parse_price_history(body) when is_map(body) do
    history = Map.get(body, "history", [])

    Enum.map(history, fn point ->
      %{
        timestamp: Map.get(point, "t"),
        price: parse_float(Map.get(point, "p"))
      }
    end)
  end

  defp parse_price_history(_), do: []

  defp extract_snapshots_from_event(event) when is_map(event) do
    markets = Map.get(event, "markets", [])
    event_id = Map.get(event, "id")

    # Extract epoch from slug (btc-updown-15m-EPOCH)
    epoch =
      case Map.get(event, "slug", "") |> String.split("-") |> List.last() do
        epoch_str ->
          case Integer.parse(epoch_str) do
            {epoch, _} -> epoch
            :error -> nil
          end
      end

    Enum.map(markets, fn market ->
      build_snapshot_from_market(market, epoch, event_id)
    end)
    |> Enum.filter(& &1)
  end

  defp extract_snapshots_from_event(_), do: []

  defp build_snapshot_from_market(market, epoch, _event_id) do
    prices_json = Map.get(market, "outcomePrices", "[]")

    case Jason.decode(prices_json) do
      {:ok, [up_price_str, down_price_str]} ->
        up_price = parse_float(up_price_str)
        down_price = parse_float(down_price_str)

        if up_price && down_price && epoch do
          timestamp = DateTime.from_unix!(epoch)

          %{
            market_id: "btc-15m-#{epoch}",
            token_id: Map.get(market, "conditionId"),
            yes_price: up_price,
            no_price: down_price,
            volume: parse_float(Map.get(market, "volume")),
            liquidity: parse_float(Map.get(market, "liquidity")),
            timestamp: timestamp,
            # Additional fields for historical data
            epoch: epoch,
            outcomes: Map.get(market, "outcomes"),
            clob_token_ids: Map.get(market, "clobTokenIds"),
            end_date: Map.get(market, "endDate"),
            resolved: Map.get(market, "closed", false)
          }
        else
          nil
        end

      _ ->
        nil
    end
  end

  # ============================================================================
  # PRIVATE - Pagination
  # ============================================================================

  defp fetch_activity_pages(_market_id, _offset, 0, _rate_limit_ms, acc) do
    {:ok, Enum.reverse(acc) |> List.flatten()}
  end

  defp fetch_activity_pages(market_id, offset, pages_left, rate_limit_ms, acc) do
    case fetch_market_activity(market_id, offset: offset) do
      {:ok, []} ->
        {:ok, Enum.reverse(acc) |> List.flatten()}

      {:ok, activity} when is_list(activity) ->
        Process.sleep(rate_limit_ms)
        next_offset = offset + length(activity)

        if length(activity) < @max_activity_per_request do
          {:ok, Enum.reverse([activity | acc]) |> List.flatten()}
        else
          fetch_activity_pages(market_id, next_offset, pages_left - 1, rate_limit_ms, [
            activity | acc
          ])
        end

      {:ok, _} ->
        {:ok, Enum.reverse(acc) |> List.flatten()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # PRIVATE - Utilities
  # ============================================================================

  defp ensure_data_dir do
    File.mkdir_p!(@data_dir)
  end

  defp parse_float(nil), do: nil
  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end
end
