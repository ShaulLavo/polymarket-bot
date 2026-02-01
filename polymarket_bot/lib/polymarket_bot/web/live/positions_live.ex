defmodule PolymarketBot.Web.PositionsLive do
  @moduledoc """
  Positions tracking LiveView - Display open positions and P&L.
  """
  use PolymarketBot.Web, :live_view

  @trade_history_placeholder """
  +---------------------------------------------------------+
  |                    TRADE HISTORY                        |
  +---------------------------------------------------------+
  |  Connect wallet to view historical trades               |
  |                                                         |
  |  > Pending implementation                               |
  |  > Will show closed positions                           |
  |  > Realized P&L breakdown                               |
  +---------------------------------------------------------+
  """

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PolymarketBot.PubSub, "positions")
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "Positions")
     |> assign(:positions, [])
     |> assign(:total_pnl, 0.0)
     |> assign(:total_value, 0.0)
     |> assign(:realized_pnl, 0.0)
     |> assign(:unrealized_pnl, 0.0)
     |> load_positions()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_positions(socket)}
  end

  @impl true
  def handle_info({:position_update, _data}, socket) do
    {:noreply, load_positions(socket)}
  end

  defp load_positions(socket) do
    # For now, return demo positions
    # In production, this would query actual positions from a positions table
    demo_positions = [
      %{
        id: 1,
        market: "BTC 15-min UP",
        side: :long,
        entry_price: 0.48,
        current_price: 0.52,
        size: 100,
        entry_time: DateTime.utc_now() |> DateTime.add(-3600, :second),
        pnl: 4.0,
        pnl_pct: 8.33
      },
      %{
        id: 2,
        market: "ETH Weekly > $3500",
        side: :long,
        entry_price: 0.35,
        current_price: 0.38,
        size: 50,
        entry_time: DateTime.utc_now() |> DateTime.add(-7200, :second),
        pnl: 1.5,
        pnl_pct: 8.57
      },
      %{
        id: 3,
        market: "Fed Rate Cut Jan",
        side: :gabagool,
        entry_price: 0.97,
        current_price: 1.0,
        size: 200,
        entry_time: DateTime.utc_now() |> DateTime.add(-86400, :second),
        pnl: 6.0,
        pnl_pct: 3.09
      }
    ]

    total_pnl = demo_positions |> Enum.map(& &1.pnl) |> Enum.sum()
    total_value = demo_positions |> Enum.map(&(&1.current_price * &1.size)) |> Enum.sum()

    socket
    |> assign(:positions, demo_positions)
    |> assign(:total_pnl, total_pnl)
    |> assign(:total_value, total_value)
    |> assign(:unrealized_pnl, total_pnl)
    |> assign(:realized_pnl, 0.0)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div class="text-xs text-green-500/70">
          [POSITION TRACKER] Real-time portfolio monitoring
        </div>
        <div class="text-xs text-amber-400">
          <span class="animate-pulse">*</span> DEMO MODE - Connect wallet for live data
        </div>
      </div>

      <!-- Portfolio Summary -->
      <div class="grid grid-cols-4 gap-4">
        <.stat
          label="TOTAL VALUE"
          value={format_currency(@total_value)}
        />
        <.stat
          label="UNREALIZED P&L"
          value={format_currency(@unrealized_pnl)}
          trend={pnl_trend(@unrealized_pnl)}
        />
        <.stat
          label="REALIZED P&L"
          value={format_currency(@realized_pnl)}
          trend={pnl_trend(@realized_pnl)}
        />
        <.stat
          label="OPEN POSITIONS"
          value={Integer.to_string(length(@positions))}
        />
      </div>

      <!-- Positions Table -->
      <.panel title="OPEN POSITIONS">
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-green-500/50 border-b border-green-500/20">
                <th class="pb-2">ID</th>
                <th class="pb-2">MARKET</th>
                <th class="pb-2">TYPE</th>
                <th class="pb-2 text-right">ENTRY</th>
                <th class="pb-2 text-right">CURRENT</th>
                <th class="pb-2 text-right">SIZE</th>
                <th class="pb-2 text-right">P&L</th>
                <th class="pb-2 text-right">P&L %</th>
                <th class="pb-2 text-right">AGE</th>
                <th class="pb-2 text-right">ACTION</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={pos <- @positions} class="border-b border-green-500/10 hover:bg-green-900/20">
                <td class="py-3 text-amber-400">#<%= pos.id %></td>
                <td class="py-3"><%= pos.market %></td>
                <td class="py-3">
                  <span class={[
                    "px-2 py-0.5 border text-xs",
                    pos.side == :long && "border-green-500/50 text-green-400",
                    pos.side == :short && "border-red-500/50 text-red-400",
                    pos.side == :gabagool && "border-amber-500/50 text-amber-400"
                  ]}>
                    <%= pos.side |> Atom.to_string() |> String.upcase() %>
                  </span>
                </td>
                <td class="py-3 text-right"><%= format_price(pos.entry_price) %></td>
                <td class="py-3 text-right"><%= format_price(pos.current_price) %></td>
                <td class="py-3 text-right"><%= pos.size %></td>
                <td class={[
                  "py-3 text-right font-bold",
                  pos.pnl >= 0 && "text-green-400",
                  pos.pnl < 0 && "text-red-400"
                ]}>
                  <%= if pos.pnl >= 0, do: "+", else: "" %><%= format_currency(pos.pnl) %>
                </td>
                <td class={[
                  "py-3 text-right",
                  pos.pnl_pct >= 0 && "text-green-400",
                  pos.pnl_pct < 0 && "text-red-400"
                ]}>
                  <%= if pos.pnl_pct >= 0, do: "+", else: "" %><%= :erlang.float_to_binary(pos.pnl_pct, decimals: 2) %>%
                </td>
                <td class="py-3 text-right text-green-500/70">
                  <%= format_age(pos.entry_time) %>
                </td>
                <td class="py-3 text-right">
                  <button class="text-red-400 hover:text-red-300 border border-red-500/30 px-2 py-0.5 text-xs hover:bg-red-900/30">
                    CLOSE
                  </button>
                </td>
              </tr>
              <tr :if={@positions == []}>
                <td colspan="10" class="py-8 text-center text-green-500/50">
                  NO OPEN POSITIONS<.cursor />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <!-- Position History (placeholder) -->
      <.panel title="RECENT TRADES">
        <div class="text-center py-8 text-green-500/50">
          <pre class="text-xs"><%= trade_history_placeholder() %></pre>
        </div>
      </.panel>

      <!-- Risk Metrics -->
      <.panel title="RISK ANALYSIS">
        <div class="grid grid-cols-3 gap-6">
          <div class="space-y-2">
            <div class="text-xs text-green-500/50">[EXPOSURE]</div>
            <div class="text-sm">
              <div class="flex justify-between mb-1">
                <span>Long Exposure:</span>
                <span class="text-green-400">$150.00</span>
              </div>
              <div class="flex justify-between mb-1">
                <span>Short Exposure:</span>
                <span class="text-red-400">$0.00</span>
              </div>
              <div class="flex justify-between">
                <span>Net Exposure:</span>
                <span class="text-amber-400">$150.00</span>
              </div>
            </div>
          </div>

          <div class="space-y-2">
            <div class="text-xs text-green-500/50">[CONCENTRATION]</div>
            <div class="text-sm space-y-1">
              <div class="flex items-center gap-2">
                <span class="w-20">BTC:</span>
                <.progress value={60} class="flex-1" />
              </div>
              <div class="flex items-center gap-2">
                <span class="w-20">ETH:</span>
                <.progress value={25} class="flex-1" />
              </div>
              <div class="flex items-center gap-2">
                <span class="w-20">Other:</span>
                <.progress value={15} class="flex-1" />
              </div>
            </div>
          </div>

          <div class="space-y-2">
            <div class="text-xs text-green-500/50">[ALERTS]</div>
            <div class="text-sm space-y-1">
              <div class="text-green-400">* All positions healthy</div>
              <div class="text-green-500/50">* No liquidation risk</div>
              <div class="text-green-500/50">* Within risk limits</div>
            </div>
          </div>
        </div>
      </.panel>
    </div>
    """
  end

  # Helpers

  defp trade_history_placeholder, do: @trade_history_placeholder

  defp format_price(price), do: :erlang.float_to_binary(price, decimals: 4)

  defp format_currency(amount) when amount >= 0 do
    "$#{:erlang.float_to_binary(amount, decimals: 2)}"
  end

  defp format_currency(amount) do
    "-$#{:erlang.float_to_binary(abs(amount), decimals: 2)}"
  end

  defp pnl_trend(pnl) when pnl > 0, do: :up
  defp pnl_trend(pnl) when pnl < 0, do: :down
  defp pnl_trend(_), do: nil

  defp format_age(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end
end
