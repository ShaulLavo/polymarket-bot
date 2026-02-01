defmodule PolymarketBot.Web.DashboardLive do
  @moduledoc """
  Main dashboard LiveView - BTC 15-min prices, positions, and P&L.
  Terminal/hacker aesthetic with real-time updates.
  """
  use PolymarketBot.Web, :live_view

  alias PolymarketBot.API

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to price updates
      Phoenix.PubSub.subscribe(PolymarketBot.PubSub, "btc_15m_prices")
      # Schedule periodic refresh
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:btc_price, nil)
     |> assign(:btc_up_price, nil)
     |> assign(:btc_down_price, nil)
     |> assign(:spread, nil)
     |> assign(:last_update, nil)
     |> assign(:price_history, [])
     |> assign(:opportunities, [])
     |> assign(:total_pnl, 0.0)
     |> assign(:open_positions, 0)
     |> assign(:loading, true)
     |> load_initial_data()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_btc_data(socket)}
  end

  @impl true
  def handle_info({:btc_price_update, data}, socket) do
    {:noreply,
     socket
     |> assign(:btc_up_price, data.up_price)
     |> assign(:btc_down_price, data.down_price)
     |> assign(:spread, data.spread)
     |> assign(:last_update, DateTime.utc_now())
     |> update_price_history(data)}
  end

  defp load_initial_data(socket) do
    socket
    |> load_btc_data()
    |> load_opportunities()
    |> assign(:loading, false)
  end

  defp load_btc_data(socket) do
    case API.get_btc_15m_event() do
      {:ok, event} ->
        markets = event["markets"] || []

        case parse_btc_prices(markets) do
          {:ok, up_price, down_price} ->
            spread = 1.0 - (up_price + down_price)

            socket
            |> assign(:btc_up_price, up_price)
            |> assign(:btc_down_price, down_price)
            |> assign(:spread, spread)
            |> assign(:last_update, DateTime.utc_now())
            |> update_price_history(%{up_price: up_price, down_price: down_price, spread: spread})

          _ ->
            socket
        end

      {:error, _} ->
        socket
    end
  end

  defp load_opportunities(socket) do
    case API.get_markets(limit: 20) do
      {:ok, markets} ->
        opps =
          markets
          |> Enum.map(fn market ->
            case API.parse_prices(market) do
              {:ok, {yes, no}} ->
                spread = 1.0 - (yes + no)

                if spread > 0.01 do
                  %{
                    question: market["question"] |> String.slice(0, 50),
                    yes: yes,
                    no: no,
                    spread: spread
                  }
                end

              _ ->
                nil
            end
          end)
          |> Enum.filter(& &1)
          |> Enum.sort_by(& &1.spread, :desc)
          |> Enum.take(5)

        assign(socket, :opportunities, opps)

      _ ->
        socket
    end
  end

  defp parse_btc_prices(markets) do
    case markets do
      [market | _] ->
        prices_json = Map.get(market, "outcomePrices", "[]")

        case Jason.decode(prices_json) do
          {:ok, [up_str, down_str]} ->
            up = parse_price(up_str)
            down = parse_price(down_str)
            if up && down, do: {:ok, up, down}, else: :error

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp parse_price(str) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_price(n) when is_number(n), do: n * 1.0
  defp parse_price(_), do: nil

  defp update_price_history(socket, data) do
    entry = %{
      time: DateTime.utc_now(),
      up: data.up_price,
      down: data.down_price,
      spread: data.spread
    }

    history = [entry | socket.assigns.price_history] |> Enum.take(60)
    assign(socket, :price_history, history)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Status Bar -->
      <div class="flex items-center justify-between text-xs text-green-500/70">
        <div class="flex items-center gap-4">
          <span>[SYS] POLYMARKET TERMINAL ACTIVE</span>
          <span :if={@loading} class="text-amber-400 animate-pulse">LOADING...</span>
        </div>
        <div class="flex items-center gap-4">
          <span>REFRESH: <%= @refresh_interval / 1000 %>s</span>
          <span :if={@last_update}>
            LAST: <%= Calendar.strftime(@last_update, "%H:%M:%S") %>
          </span>
        </div>
      </div>

      <!-- Main Grid -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- BTC 15-min Panel -->
        <.panel title="BTC 15-MIN MARKET" class="lg:col-span-2">
          <div class="space-y-4">
            <!-- Current Prices -->
            <div class="grid grid-cols-3 gap-4">
              <.stat
                label="UP PRICE"
                value={format_price(@btc_up_price)}
                trend={if @btc_up_price && @btc_up_price > 0.5, do: :up, else: :down}
              />
              <.stat
                label="DOWN PRICE"
                value={format_price(@btc_down_price)}
                trend={if @btc_down_price && @btc_down_price > 0.5, do: :up, else: :down}
              />
              <.stat
                label="SPREAD"
                value={format_pct(@spread)}
                trend={if @spread && @spread > 0.02, do: :up, else: nil}
              />
            </div>

            <!-- ASCII Price Chart -->
            <div class="border border-green-500/20 bg-black p-4">
              <div class="text-xs text-green-500/50 mb-2">[SPREAD HISTORY - LAST 60 SAMPLES]</div>
              <pre class="text-green-400 text-xs leading-tight"><%= render_ascii_chart(@price_history) %></pre>
            </div>

            <!-- Market Info -->
            <div class="text-xs text-green-500/70 space-y-1">
              <div>> Market: Bitcoin 15-Minute Resolution</div>
              <div>> Type: Binary outcome (UP/DOWN)</div>
              <div :if={@spread && @spread > 0.015}>
                <span class="text-amber-400 animate-pulse">> ALERT: Arbitrage opportunity detected!</span>
              </div>
            </div>
          </div>
        </.panel>

        <!-- Stats Panel -->
        <.panel title="PORTFOLIO STATS">
          <div class="space-y-4">
            <.stat label="TOTAL P&L" value={format_currency(@total_pnl)} trend={pnl_trend(@total_pnl)} />
            <.stat label="OPEN POSITIONS" value={Integer.to_string(@open_positions)} />

            <div class="border-t border-green-500/20 pt-4 mt-4">
              <div class="text-xs text-green-500/50 mb-2">[QUICK ACTIONS]</div>
              <div class="space-y-2">
                <.button class="w-full">
                  SCAN MARKETS
                </.button>
                <.link navigate={~p"/backtest"} class="block">
                  <.button class="w-full">
                    RUN BACKTEST
                  </.button>
                </.link>
              </div>
            </div>
          </div>
        </.panel>
      </div>

      <!-- Opportunities Panel -->
      <.panel title="ARBITRAGE OPPORTUNITIES">
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-green-500/50 border-b border-green-500/20">
                <th class="pb-2">MARKET</th>
                <th class="pb-2 text-right">YES</th>
                <th class="pb-2 text-right">NO</th>
                <th class="pb-2 text-right">SPREAD</th>
                <th class="pb-2 text-right">STATUS</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={opp <- @opportunities} class="border-b border-green-500/10 hover:bg-green-900/20">
                <td class="py-2 pr-4 truncate max-w-xs"><%= opp.question %>...</td>
                <td class="py-2 text-right"><%= format_price(opp.yes) %></td>
                <td class="py-2 text-right"><%= format_price(opp.no) %></td>
                <td class={[
                  "py-2 text-right font-bold",
                  opp.spread > 0.02 && "text-green-400",
                  opp.spread <= 0.02 && "text-amber-400"
                ]}>
                  <%= format_pct(opp.spread) %>
                </td>
                <td class="py-2 text-right">
                  <span :if={opp.spread > 0.02} class="text-green-400">[TRADEABLE]</span>
                  <span :if={opp.spread <= 0.02} class="text-amber-400">[WATCH]</span>
                </td>
              </tr>
              <tr :if={@opportunities == []}>
                <td colspan="5" class="py-4 text-center text-green-500/50">
                  NO OPPORTUNITIES FOUND<.cursor />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <!-- Terminal Output -->
      <.panel title="SYSTEM LOG">
        <div class="h-32 overflow-y-auto text-xs text-green-500/70 font-mono space-y-1">
          <div>[<%= format_time(DateTime.utc_now()) %>] Terminal initialized</div>
          <div>[<%= format_time(DateTime.utc_now()) %>] Connected to Polymarket API</div>
          <div :if={@btc_up_price}>
            [<%= format_time(@last_update) %>] BTC 15m prices updated: UP=<%= format_price(@btc_up_price) %> DOWN=<%= format_price(@btc_down_price) %>
          </div>
          <div :if={length(@opportunities) > 0}>
            [<%= format_time(DateTime.utc_now()) %>] Found <%= length(@opportunities) %> arbitrage opportunities
          </div>
          <div class="text-green-400">> Awaiting commands<.cursor /></div>
        </div>
      </.panel>
    </div>
    """
  end

  # Helper functions

  defp format_price(nil), do: "-.--"
  defp format_price(price), do: :erlang.float_to_binary(price, decimals: 4)

  defp format_pct(nil), do: "--%"
  defp format_pct(pct), do: "#{:erlang.float_to_binary(pct * 100, decimals: 2)}%"

  defp format_currency(amount) when amount >= 0,
    do: "$#{:erlang.float_to_binary(amount, decimals: 2)}"

  defp format_currency(amount), do: "-$#{:erlang.float_to_binary(abs(amount), decimals: 2)}"

  defp format_time(nil), do: "--:--:--"
  defp format_time(dt), do: Calendar.strftime(dt, "%H:%M:%S")

  defp pnl_trend(pnl) when pnl > 0, do: :up
  defp pnl_trend(pnl) when pnl < 0, do: :down
  defp pnl_trend(_), do: nil

  defp render_ascii_chart(history) when length(history) < 2 do
    """
    SPREAD %
       5 |
       4 |
       3 |                    NO DATA
       2 |
       1 |
       0 +----------------------------------------
    """
  end

  defp render_ascii_chart(history) do
    spreads = history |> Enum.reverse() |> Enum.map(& &1.spread) |> Enum.take(40)
    max_spread = max(Enum.max(spreads), 0.05)
    height = 6

    lines =
      for row <- (height - 1)..0 do
        threshold = max_spread * (row / height)
        label = :erlang.float_to_binary(threshold * 100, decimals: 1) |> String.pad_leading(4)

        chars =
          spreads
          |> Enum.map(fn spread ->
            if spread >= threshold, do: "#", else: " "
          end)
          |> Enum.join("")

        "#{label} |#{chars}"
      end

    x_axis = "     +" <> String.duplicate("-", length(spreads))

    Enum.join(lines ++ [x_axis], "\n")
  end
end
