defmodule PolymarketBot.WebSocket do
  @moduledoc """
  WebSocket client for real-time Polymarket price updates.

  Connects to Polymarket's CLOB WebSocket API and subscribes to price updates
  for specified markets. Price updates are automatically saved to the database.
  """
  use WebSockex
  require Logger

  alias PolymarketBot.Repo
  alias PolymarketBot.Schema.PriceSnapshot

  @ws_url "wss://ws-subscriptions-clob.polymarket.com/ws/market"
  @heartbeat_interval 30_000
  @reconnect_delay 5_000

  defstruct [:subscribed_markets, :last_heartbeat, :reconnect_attempts]

  # Client API

  def start_link(opts \\ []) do
    state = %__MODULE__{
      subscribed_markets: Keyword.get(opts, :markets, []),
      last_heartbeat: DateTime.utc_now(),
      reconnect_attempts: 0
    }

    WebSockex.start_link(@ws_url, __MODULE__, state, name: __MODULE__)
  end

  @doc """
  Subscribe to price updates for a specific market.
  """
  def subscribe(market_id) when is_binary(market_id) do
    subscribe([market_id])
  end

  def subscribe(market_ids) when is_list(market_ids) do
    message = Jason.encode!(%{
      type: "subscribe",
      channel: "market",
      markets: market_ids
    })

    WebSockex.send_frame(__MODULE__, {:text, message})
  end

  @doc """
  Unsubscribe from price updates for a specific market.
  """
  def unsubscribe(market_id) when is_binary(market_id) do
    unsubscribe([market_id])
  end

  def unsubscribe(market_ids) when is_list(market_ids) do
    message = Jason.encode!(%{
      type: "unsubscribe",
      channel: "market",
      markets: market_ids
    })

    WebSockex.send_frame(__MODULE__, {:text, message})
  end

  # WebSockex Callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("[WebSocket] Connected to Polymarket")

    # Schedule heartbeat
    Process.send_after(self(), :heartbeat, @heartbeat_interval)

    # Subscribe to any pre-configured markets
    if state.subscribed_markets != [] do
      message = Jason.encode!(%{
        type: "subscribe",
        channel: "market",
        markets: state.subscribed_markets
      })

      {:reply, {:text, message}, %{state | reconnect_attempts: 0}}
    else
      {:ok, %{state | reconnect_attempts: 0}}
    end
  end

  @impl true
  def handle_frame({:text, message}, state) do
    case Jason.decode(message) do
      {:ok, data} ->
        handle_message(data, state)

      {:error, reason} ->
        Logger.warning("[WebSocket] Failed to decode message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Send ping to keep connection alive
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
    {:reply, {:ping, ""}, %{state | last_heartbeat: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def handle_pong(_pong, state) do
    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("[WebSocket] Disconnected: #{inspect(reason)}")

    new_attempts = state.reconnect_attempts + 1
    delay = min(trunc(@reconnect_delay * :math.pow(2, new_attempts - 1)), 60_000)

    Logger.info("[WebSocket] Reconnecting in #{delay}ms (attempt #{new_attempts})")

    {:reconnect, delay, %{state | reconnect_attempts: new_attempts}}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("[WebSocket] Terminating: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp handle_message(%{"event_type" => "price_change"} = data, state) do
    handle_price_change(data)
    {:ok, state}
  end

  defp handle_message(%{"type" => "subscribed", "markets" => markets}, state) do
    Logger.info("[WebSocket] Subscribed to markets: #{inspect(markets)}")
    new_markets = Enum.uniq(state.subscribed_markets ++ markets)
    {:ok, %{state | subscribed_markets: new_markets}}
  end

  defp handle_message(%{"type" => "unsubscribed", "markets" => markets}, state) do
    Logger.info("[WebSocket] Unsubscribed from markets: #{inspect(markets)}")
    new_markets = state.subscribed_markets -- markets
    {:ok, %{state | subscribed_markets: new_markets}}
  end

  defp handle_message(%{"type" => "error", "message" => error_msg}, state) do
    Logger.error("[WebSocket] Error from server: #{error_msg}")
    {:ok, state}
  end

  defp handle_message(%{"type" => "heartbeat"}, state) do
    {:ok, state}
  end

  defp handle_message(data, state) do
    # Handle price change messages (common format from Polymarket)
    case extract_price_data(data) do
      {:ok, price_data} ->
        save_price_update(price_data)
        {:ok, state}

      :ignore ->
        Logger.debug("[WebSocket] Unhandled message type: #{inspect(data)}")
        {:ok, state}
    end
  end

  # Handle Polymarket's price_change event format
  defp handle_price_change(%{"asset_id" => asset_id, "market" => market_id, "changes" => changes, "timestamp" => ts}) do
    # Extract the best price from changes (typically we want the most recent/relevant)
    price = case changes do
      [%{"price" => p} | _] -> parse_price(p)
      _ -> nil
    end

    if price do
      timestamp = parse_timestamp(parse_timestamp_string(ts))

      attrs = %{
        market_id: market_id,
        token_id: asset_id,
        yes_price: price,
        no_price: 1.0 - price,
        timestamp: timestamp
      }

      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)

      case Repo.insert(changeset) do
        {:ok, _snapshot} ->
          Logger.debug("[WebSocket] Saved price change for market #{market_id}")
          :ok

        {:error, changeset} ->
          Logger.warning("[WebSocket] Failed to save price change: #{inspect(changeset.errors)}")
          :error
      end
    else
      :ok
    end
  end

  defp handle_price_change(_), do: :ok

  # Parse timestamp string (Polymarket sends as string of milliseconds)
  defp parse_timestamp_string(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {int, _} -> int
      :error -> ts
    end
  end
  defp parse_timestamp_string(ts), do: ts

  defp extract_price_data(%{"market" => market_id, "price" => price} = data) do
    {:ok, %{
      "type" => "price_update",
      "market_id" => market_id,
      "token_id" => Map.get(data, "token_id") || Map.get(data, "asset_id"),
      "yes_price" => parse_price(price),
      "no_price" => 1.0 - parse_price(price),
      "timestamp" => Map.get(data, "timestamp") || DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp extract_price_data(%{"asset_id" => token_id, "price" => price} = data) do
    {:ok, %{
      "type" => "price_update",
      "market_id" => Map.get(data, "market_id", token_id),
      "token_id" => token_id,
      "yes_price" => parse_price(price),
      "no_price" => 1.0 - parse_price(price),
      "timestamp" => Map.get(data, "timestamp") || DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp extract_price_data(_), do: :ignore

  defp parse_price(price) when is_float(price), do: price
  defp parse_price(price) when is_integer(price), do: price / 1.0
  defp parse_price(price) when is_binary(price) do
    case Float.parse(price) do
      {val, _} -> val
      :error -> 0.0
    end
  end
  defp parse_price(_), do: 0.0

  defp save_price_update(%{"type" => "price_update"} = data) do
    timestamp = parse_timestamp(data["timestamp"])

    attrs = %{
      market_id: data["market_id"],
      token_id: data["token_id"],
      yes_price: data["yes_price"],
      no_price: data["no_price"],
      timestamp: timestamp
    }

    changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)

    case Repo.insert(changeset) do
      {:ok, _snapshot} ->
        Logger.debug("[WebSocket] Saved price update for market #{data["market_id"]}")
        :ok

      {:error, changeset} ->
        Logger.warning("[WebSocket] Failed to save price update: #{inspect(changeset.errors)}")
        :error
    end
  end

  defp save_price_update(_), do: :ok

  defp parse_timestamp(nil), do: DateTime.utc_now()
  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_timestamp(ts) when is_integer(ts) do
    case DateTime.from_unix(ts, :millisecond) do
      {:ok, dt} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end
  defp parse_timestamp(_), do: DateTime.utc_now()
end
