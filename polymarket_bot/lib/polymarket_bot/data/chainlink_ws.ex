defmodule PolymarketBot.Data.ChainlinkWS do
  @moduledoc """
  WebSocket client for real-time Chainlink BTC/USD price updates.

  Connects to Polymarket's live data WebSocket and subscribes to
  Chainlink price feeds for BTC/USD.
  """
  use WebSockex
  require Logger

  @default_url "wss://ws-live-data.polymarket.com"
  @heartbeat_interval 30_000
  @reconnect_delay 5_000

  defstruct [
    :last_price,
    :last_updated_at,
    :callback,
    :reconnect_attempts,
    :subscribed
  ]

  # Client API

  @doc """
  Starts the Chainlink WebSocket client.

  ## Options

  - `:callback` - Function to call on price updates: fn(price, timestamp) -> any
  - `:url` - WebSocket URL (default: wss://ws-live-data.polymarket.com)
  - `:name` - Process name (default: __MODULE__)

  ## Examples

      iex> PolymarketBot.Data.ChainlinkWS.start_link(
      ...>   callback: fn price, ts -> IO.puts("BTC: $\#{price}") end
      ...> )
      {:ok, pid}

  """
  def start_link(opts \\ []) do
    url = Keyword.get(opts, :url, get_config(:url, @default_url))
    name = Keyword.get(opts, :name, __MODULE__)
    callback = Keyword.get(opts, :callback)

    state = %__MODULE__{
      last_price: nil,
      last_updated_at: nil,
      callback: callback,
      reconnect_attempts: 0,
      subscribed: false
    }

    WebSockex.start_link(url, __MODULE__, state, name: name)
  end

  @doc """
  Gets the last known BTC price.

  ## Examples

      iex> PolymarketBot.Data.ChainlinkWS.get_last_price()
      {:ok, %{price: 95234.56, updated_at: ~U[2024-01-15 12:00:00Z]}}

  """
  @spec get_last_price(atom()) :: {:ok, map()} | {:error, :no_price}
  def get_last_price(name \\ __MODULE__) do
    try do
      case :sys.get_state(name) do
        %{last_price: nil} ->
          {:error, :no_price}

        %{last_price: price, last_updated_at: updated_at} ->
          {:ok, %{price: price, updated_at: updated_at, source: :chainlink_ws}}
      end
    catch
      :exit, _ -> {:error, :not_running}
    end
  end

  @doc """
  Subscribes to crypto price updates.
  """
  def subscribe(name \\ __MODULE__) do
    WebSockex.cast(name, :subscribe)
  end

  # WebSockex Callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("[ChainlinkWS] Connected to Polymarket live data")

    # Schedule heartbeat
    Process.send_after(self(), :heartbeat, @heartbeat_interval)

    # Subscribe to crypto prices
    Process.send_after(self(), :subscribe, 100)

    {:ok, %{state | reconnect_attempts: 0}}
  end

  @impl true
  def handle_cast(:subscribe, state) do
    message =
      Jason.encode!(%{
        "type" => "subscribe",
        "channel" => "crypto_prices_chainlink"
      })

    {:reply, {:text, message}, state}
  end

  @impl true
  def handle_frame({:text, message}, state) do
    case Jason.decode(message) do
      {:ok, data} ->
        handle_message(data, state)

      {:error, _reason} ->
        {:ok, state}
    end
  end

  @impl true
  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
    {:reply, {:ping, ""}, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    if not state.subscribed do
      message =
        Jason.encode!(%{
          "type" => "subscribe",
          "channel" => "crypto_prices_chainlink"
        })

      {:reply, {:text, message}, state}
    else
      {:ok, state}
    end
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
    Logger.warning("[ChainlinkWS] Disconnected: #{inspect(reason)}")

    new_attempts = state.reconnect_attempts + 1
    delay = min(trunc(@reconnect_delay * :math.pow(2, new_attempts - 1)), 60_000)

    Logger.info("[ChainlinkWS] Reconnecting in #{delay}ms (attempt #{new_attempts})")

    {:reconnect, delay, %{state | reconnect_attempts: new_attempts, subscribed: false}}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("[ChainlinkWS] Terminating: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp handle_message(%{"type" => "subscribed", "channel" => channel}, state) do
    Logger.info("[ChainlinkWS] Subscribed to #{channel}")
    {:ok, %{state | subscribed: true}}
  end

  defp handle_message(%{"type" => "price_update", "data" => data}, state) do
    handle_price_data(data, state)
  end

  defp handle_message(%{"type" => "crypto_price", "data" => data}, state) do
    handle_price_data(data, state)
  end

  # Handle various price data formats from Polymarket
  defp handle_message(%{"asset" => "BTC"} = data, state) do
    handle_btc_price(data, state)
  end

  defp handle_message(%{"symbol" => "BTC" <> _} = data, state) do
    handle_btc_price(data, state)
  end

  defp handle_message(%{"prices" => prices}, state) when is_map(prices) do
    case Map.get(prices, "BTC") || Map.get(prices, "BTCUSD") do
      nil -> {:ok, state}
      price_data -> handle_btc_price(price_data, state)
    end
  end

  defp handle_message(%{"type" => "heartbeat"}, state) do
    {:ok, state}
  end

  defp handle_message(%{"type" => "error", "message" => error_msg}, state) do
    Logger.error("[ChainlinkWS] Error from server: #{error_msg}")
    {:ok, state}
  end

  defp handle_message(_data, state) do
    {:ok, state}
  end

  defp handle_price_data(data, state) when is_map(data) do
    # Look for BTC price in the data
    btc_price = extract_btc_price(data)

    if btc_price do
      handle_btc_price(%{"price" => btc_price}, state)
    else
      {:ok, state}
    end
  end

  defp handle_price_data(_, state), do: {:ok, state}

  defp handle_btc_price(data, state) do
    price = parse_price(data["price"])
    timestamp = parse_timestamp(data["timestamp"] || data["updated_at"])

    if price do
      updated_at = timestamp || DateTime.utc_now()

      new_state = %{state | last_price: price, last_updated_at: updated_at}

      # Call the callback if provided
      if is_function(state.callback) do
        state.callback.(price, updated_at)
      end

      Logger.debug("[ChainlinkWS] BTC price: $#{price}")

      {:ok, new_state}
    else
      {:ok, state}
    end
  end

  defp extract_btc_price(%{"BTC" => %{"price" => price}}), do: price
  defp extract_btc_price(%{"BTC" => price}) when is_number(price), do: price
  defp extract_btc_price(%{"BTCUSD" => %{"price" => price}}), do: price
  defp extract_btc_price(%{"BTCUSD" => price}) when is_number(price), do: price
  defp extract_btc_price(%{"btc" => %{"price" => price}}), do: price
  defp extract_btc_price(%{"btc" => price}) when is_number(price), do: price
  defp extract_btc_price(_), do: nil

  defp parse_price(price) when is_float(price), do: price
  defp parse_price(price) when is_integer(price), do: price * 1.0

  defp parse_price(price) when is_binary(price) do
    case Float.parse(price) do
      {val, _} -> val
      :error -> nil
    end
  end

  defp parse_price(_), do: nil

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_timestamp(ts) when is_integer(ts) do
    # Assume milliseconds if large enough
    unit = if ts > 10_000_000_000, do: :millisecond, else: :second

    case DateTime.from_unix(ts, unit) do
      {:ok, dt} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_timestamp(_), do: nil

  defp get_config(key, default) do
    Application.get_env(:polymarket_bot, :chainlink_ws, [])
    |> Keyword.get(key, default)
  end
end
