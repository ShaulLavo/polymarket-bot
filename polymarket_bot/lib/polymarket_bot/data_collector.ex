defmodule PolymarketBot.DataCollector do
  @moduledoc """
  GenServer that periodically collects and persists Polymarket data.

  Collects:
  - Price snapshots every minute
  - Order book snapshots every 5 minutes
  - Market metadata updates every hour
  - BTC 15-min market snapshots every 30 seconds
  """
  use GenServer
  require Logger

  alias PolymarketBot.{API, Repo}
  alias PolymarketBot.Schema.{Market, PriceSnapshot, OrderbookSnapshot}

  # Collect prices every minute
  @price_interval :timer.minutes(1)
  # Collect order books every 5 minutes
  @orderbook_interval :timer.minutes(5)
  # Update market metadata hourly
  @market_interval :timer.hours(1)
  # Collect BTC 15-min market every 30 seconds
  @btc_15m_interval :timer.seconds(30)

  # ============================================================================
  # CLIENT API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  def collect_now(type \\ :all) do
    GenServer.cast(__MODULE__, {:collect_now, type})
  end

  # ============================================================================
  # SERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("DataCollector starting...")

    # Schedule initial collections
    schedule_collection(:prices, 1000)
    schedule_collection(:orderbooks, 5000)
    schedule_collection(:markets, 10000)
    schedule_collection(:btc_15m, 2000)

    state = %{
      last_price_collection: nil,
      last_orderbook_collection: nil,
      last_market_collection: nil,
      last_btc_15m_collection: nil,
      price_count: 0,
      orderbook_count: 0,
      market_count: 0,
      btc_15m_count: 0,
      errors: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:collect_now, :all}, state) do
    state = collect_prices(state)
    state = collect_orderbooks(state)
    state = collect_markets(state)
    state = collect_btc_15m(state)
    {:noreply, state}
  end

  def handle_cast({:collect_now, :prices}, state) do
    {:noreply, collect_prices(state)}
  end

  def handle_cast({:collect_now, :orderbooks}, state) do
    {:noreply, collect_orderbooks(state)}
  end

  def handle_cast({:collect_now, :markets}, state) do
    {:noreply, collect_markets(state)}
  end

  def handle_cast({:collect_now, :btc_15m}, state) do
    {:noreply, collect_btc_15m(state)}
  end

  @impl true
  def handle_info(:collect_prices, state) do
    state = collect_prices(state)
    schedule_collection(:prices, @price_interval)
    {:noreply, state}
  end

  def handle_info(:collect_orderbooks, state) do
    state = collect_orderbooks(state)
    schedule_collection(:orderbooks, @orderbook_interval)
    {:noreply, state}
  end

  def handle_info(:collect_markets, state) do
    state = collect_markets(state)
    schedule_collection(:markets, @market_interval)
    {:noreply, state}
  end

  def handle_info(:collect_btc_15m, state) do
    state = collect_btc_15m(state)
    schedule_collection(:btc_15m, @btc_15m_interval)
    {:noreply, state}
  end

  # ============================================================================
  # COLLECTION FUNCTIONS
  # ============================================================================

  defp collect_prices(state) do
    Logger.debug("Collecting price snapshots...")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case API.get_markets(limit: 100, active: true, closed: false) do
      {:ok, markets} ->
        snapshots =
          markets
          |> Enum.map(&build_price_snapshot(&1, now))
          |> Enum.filter(& &1)

        # Batch insert
        {count, _} = Repo.insert_all(PriceSnapshot, snapshots, on_conflict: :nothing)

        Logger.info("Collected #{count} price snapshots")

        %{state | last_price_collection: now, price_count: state.price_count + count}

      {:error, reason} ->
        Logger.error("Failed to collect prices: #{inspect(reason)}")
        add_error(state, {:prices, reason, now})
    end
  end

  defp collect_orderbooks(state) do
    Logger.debug("Collecting order book snapshots...")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case API.get_markets(limit: 50, active: true, closed: false) do
      {:ok, markets} ->
        snapshots =
          markets
          |> Enum.flat_map(fn market ->
            case API.parse_token_ids(market) do
              {:ok, {yes_token, no_token}} ->
                [
                  fetch_orderbook_snapshot(yes_token, market["id"], now),
                  fetch_orderbook_snapshot(no_token, market["id"], now)
                ]

              _ ->
                []
            end
          end)
          |> Enum.filter(& &1)

        {count, _} = Repo.insert_all(OrderbookSnapshot, snapshots, on_conflict: :nothing)

        Logger.info("Collected #{count} order book snapshots")

        %{state | last_orderbook_collection: now, orderbook_count: state.orderbook_count + count}

      {:error, reason} ->
        Logger.error("Failed to collect order books: #{inspect(reason)}")
        add_error(state, {:orderbooks, reason, now})
    end
  end

  defp collect_markets(state) do
    Logger.debug("Collecting market metadata...")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case API.get_markets(limit: 200, active: true, closed: false) do
      {:ok, markets} ->
        count =
          markets
          |> Enum.map(&upsert_market/1)
          |> Enum.count(fn result -> match?({:ok, _}, result) end)

        Logger.info("Updated #{count} markets")

        %{state | last_market_collection: now, market_count: count}

      {:error, reason} ->
        Logger.error("Failed to collect markets: #{inspect(reason)}")
        add_error(state, {:markets, reason, now})
    end
  end

  defp collect_btc_15m(state) do
    Logger.debug("Collecting BTC 15-min market...")
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    epoch = div(System.os_time(:second), 900) * 900

    case API.get_btc_15m_event() do
      {:ok, event} ->
        snapshots =
          (event["markets"] || [])
          |> Enum.map(&build_btc_15m_snapshot(&1, epoch, now))
          |> Enum.filter(& &1)

        case snapshots do
          [] ->
            Logger.debug("No BTC 15-min markets found for epoch #{epoch}")
            state

          _ ->
            {count, _} = Repo.insert_all(PriceSnapshot, snapshots, on_conflict: :nothing)
            Logger.info("Collected #{count} BTC 15-min snapshots (epoch: #{epoch})")
            %{state | last_btc_15m_collection: now, btc_15m_count: state.btc_15m_count + count}
        end

      {:error, {404, _}} ->
        # Market not yet created for this epoch - this is normal
        Logger.debug("BTC 15-min market not found for epoch #{epoch}")
        state

      {:error, reason} ->
        Logger.error("Failed to collect BTC 15-min: #{inspect(reason)}")
        add_error(state, {:btc_15m, reason, now})
    end
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp schedule_collection(type, delay) do
    Process.send_after(self(), :"collect_#{type}", delay)
  end

  defp build_price_snapshot(market, timestamp) do
    case API.parse_prices(market) do
      {:ok, {yes_price, no_price}} ->
        %{
          market_id: market["id"],
          token_id: nil,
          yes_price: yes_price,
          no_price: no_price,
          volume: parse_float(market["volume"]),
          liquidity: parse_float(market["liquidity"]),
          timestamp: timestamp,
          inserted_at: timestamp,
          updated_at: timestamp
        }

      _ ->
        nil
    end
  end

  defp build_btc_15m_snapshot(market, epoch, timestamp) do
    prices_json = Map.get(market, "outcomePrices", "[]")

    case Jason.decode(prices_json) do
      {:ok, [up_price_str, down_price_str]} ->
        up_price = parse_float(up_price_str)
        down_price = parse_float(down_price_str)

        if up_price && down_price do
          # Use "btc-15m-{epoch}" as market_id for easy identification
          %{
            market_id: "btc-15m-#{epoch}",
            token_id: market["conditionId"],
            yes_price: up_price,
            no_price: down_price,
            volume: parse_float(market["volume"]),
            liquidity: parse_float(market["liquidity"]),
            timestamp: timestamp,
            inserted_at: timestamp,
            updated_at: timestamp
          }
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp fetch_orderbook_snapshot(token_id, market_id, timestamp) do
    case API.get_order_book(token_id) do
      {:ok, book} ->
        bids = book["bids"] || []
        asks = book["asks"] || []

        best_bid =
          case bids do
            [%{"price" => p} | _] -> parse_float(p)
            _ -> nil
          end

        best_ask =
          case asks do
            [%{"price" => p} | _] -> parse_float(p)
            _ -> nil
          end

        spread = if best_bid && best_ask, do: best_ask - best_bid, else: nil

        %{
          token_id: token_id,
          market_id: market_id,
          bids: Jason.encode!(bids),
          asks: Jason.encode!(asks),
          best_bid: best_bid,
          best_ask: best_ask,
          spread: spread,
          timestamp: timestamp,
          inserted_at: timestamp,
          updated_at: timestamp
        }

      {:error, _} ->
        nil
    end
  end

  defp upsert_market(market_data) do
    {yes_token, no_token} =
      case API.parse_token_ids(market_data) do
        {:ok, tokens} -> tokens
        _ -> {nil, nil}
      end

    attrs = %{
      polymarket_id: market_data["id"],
      question: market_data["question"],
      slug: market_data["slug"],
      event_id: market_data["eventId"],
      condition_id: market_data["conditionId"],
      yes_token_id: yes_token,
      no_token_id: no_token,
      outcomes: market_data["outcomes"],
      active: market_data["active"],
      closed: market_data["closed"]
    }

    case Repo.get_by(Market, polymarket_id: market_data["id"]) do
      nil ->
        %Market{}
        |> Market.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Market.changeset(attrs)
        |> Repo.update()
    end
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

  defp add_error(state, error) do
    errors = [error | Enum.take(state.errors, 99)]
    %{state | errors: errors}
  end
end
