defmodule PolymarketBot.Web.BacktestLive do
  @moduledoc """
  Backtest runner LiveView - Configure and run backtests with visual results.
  """
  use PolymarketBot.Web, :live_view

  alias PolymarketBot.Backtester
  alias PolymarketBot.Backtester.Strategies.{GabagoolArb, MeanReversion, Momentum}
  alias PolymarketBot.Repo
  alias PolymarketBot.Schema.PriceSnapshot
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Backtest")
     |> assign(:strategy, "gabagool_arb")
     |> assign(:market_id, nil)
     |> assign(:markets, load_available_markets())
     |> assign(:config, default_config("gabagool_arb"))
     |> assign(:running, false)
     |> assign(:progress, 0)
     |> assign(:results, nil)
     |> assign(:error, nil)
     |> assign(:equity_curve, [])}
  end

  @impl true
  def handle_event("select_strategy", %{"strategy" => strategy}, socket) do
    {:noreply,
     socket
     |> assign(:strategy, strategy)
     |> assign(:config, default_config(strategy))
     |> assign(:results, nil)
     |> assign(:equity_curve, [])}
  end

  @impl true
  def handle_event("select_market", %{"market_id" => market_id}, socket) do
    {:noreply, assign(socket, :market_id, market_id)}
  end

  @impl true
  def handle_event("update_config", %{"field" => field, "value" => value}, socket) do
    config = socket.assigns.config
    parsed_value = parse_config_value(value)
    new_config = Map.put(config, String.to_existing_atom(field), parsed_value)
    {:noreply, assign(socket, :config, new_config)}
  end

  @impl true
  def handle_event("run_backtest", _params, socket) do
    market_id = socket.assigns.market_id

    if is_nil(market_id) or market_id == "" do
      {:noreply, assign(socket, :error, "Please select a market")}
    else
      send(self(), :run_backtest)

      {:noreply,
       socket
       |> assign(:running, true)
       |> assign(:progress, 0)
       |> assign(:error, nil)
       |> assign(:results, nil)}
    end
  end

  @impl true
  def handle_info(:run_backtest, socket) do
    strategy_module = get_strategy_module(socket.assigns.strategy)
    market_id = socket.assigns.market_id
    config = socket.assigns.config

    # Run backtest
    backtest_opts = [
      market_id: market_id,
      strategy: strategy_module,
      strategy_config: config,
      initial_capital: 10_000.0
    ]

    case Backtester.run(backtest_opts) do
        {:ok, results} ->
          equity_curve = results[:equity_curve] || []

          {:noreply,
           socket
           |> assign(:running, false)
           |> assign(:progress, 100)
           |> assign(:results, results)
           |> assign(:equity_curve, equity_curve)}

        {:error, reason} ->
        {:noreply,
         socket
         |> assign(:running, false)
         |> assign(:error, inspect(reason))}
    end
  end

  defp load_available_markets do
    # Get unique market IDs from price snapshots
    query =
      from p in PriceSnapshot,
        select: p.market_id,
        distinct: true,
        order_by: [desc: p.timestamp],
        limit: 50

    Repo.all(query)
    |> Enum.map(fn id -> {truncate_id(id), id} end)
  end

  defp get_strategy_module("gabagool_arb"), do: GabagoolArb
  defp get_strategy_module("mean_reversion"), do: MeanReversion
  defp get_strategy_module("momentum"), do: Momentum
  defp get_strategy_module(_), do: GabagoolArb

  defp default_config("gabagool_arb") do
    %{
      entry_threshold: 0.02,
      position_size: 1.0,
      max_positions: 5,
      cost_aware_entry: true,
      min_net_spread: 0.005
    }
  end

  defp default_config("mean_reversion") do
    %{
      lookback_period: 20,
      entry_threshold: 2.0,
      exit_threshold: 0.5,
      position_size: 1.0
    }
  end

  defp default_config("momentum") do
    %{
      fast_period: 5,
      slow_period: 20,
      position_size: 1.0
    }
  end

  defp default_config(_), do: %{}

  defp parse_config_value(value) do
    case Float.parse(value) do
      {f, ""} -> f
      _ ->
        case Integer.parse(value) do
          {i, ""} -> i
          _ -> value
        end
    end
  end

  defp truncate_id(id) when byte_size(id) > 20, do: String.slice(id, 0, 20) <> "..."
  defp truncate_id(id), do: id

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div class="text-xs text-green-500/70">
          [BACKTEST ENGINE v1.0] Strategy backtesting with historical data
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Configuration Panel -->
        <.panel title="CONFIGURATION" class="lg:col-span-1">
          <div class="space-y-4">
            <!-- Strategy Selection -->
            <.select
              label="STRATEGY"
              name="strategy"
              options={[
                {"Gabagool Arbitrage", "gabagool_arb"},
                {"Mean Reversion", "mean_reversion"},
                {"Momentum", "momentum"}
              ]}
              value={@strategy}
              phx-change="select_strategy"
            />

            <!-- Market Selection -->
            <.select
              label="MARKET"
              name="market_id"
              options={[{"-- Select Market --", ""} | @markets]}
              value={@market_id || ""}
              phx-change="select_market"
            />

            <!-- Strategy Config -->
            <div class="border-t border-green-500/20 pt-4">
              <div class="text-xs text-green-500/50 mb-2">[PARAMETERS]</div>

              <div :for={{key, value} <- @config} class="mb-2">
                <.input
                  label={key |> Atom.to_string() |> String.upcase() |> String.replace("_", " ")}
                  name={Atom.to_string(key)}
                  value={value}
                  phx-blur="update_config"
                  phx-value-field={Atom.to_string(key)}
                />
              </div>
            </div>

            <!-- Run Button -->
            <div class="pt-4">
              <.button
                phx-click="run_backtest"
                disabled={@running}
                class="w-full"
              >
                <%= if @running, do: "RUNNING...", else: "EXECUTE BACKTEST" %>
              </.button>
            </div>

            <!-- Progress -->
            <div :if={@running} class="pt-2">
              <.progress value={@progress} />
            </div>

            <!-- Error -->
            <div :if={@error} class="text-red-400 text-sm border border-red-500/30 p-2 bg-red-900/20">
              [ERROR] <%= @error %>
            </div>
          </div>
        </.panel>

        <!-- Results Panel -->
        <.panel title="RESULTS" class="lg:col-span-2">
          <div :if={is_nil(@results)} class="text-center py-8 text-green-500/50">
            <div class="text-4xl mb-4">[ ]</div>
            <div>Configure and run a backtest to see results<.cursor /></div>
          </div>

          <div :if={@results} class="space-y-6">
            <!-- Key Metrics -->
            <div class="grid grid-cols-4 gap-4">
              <.stat
                label="TOTAL RETURN"
                value={format_pct(@results[:total_return] || @results[:roi_percent] || 0)}
                trend={return_trend(@results[:total_return] || @results[:roi_percent] || 0)}
              />
              <.stat
                label="SHARPE RATIO"
                value={format_decimal(@results[:sharpe_ratio])}
                trend={sharpe_trend(@results[:sharpe_ratio])}
              />
              <.stat
                label="MAX DRAWDOWN"
                value={format_pct(@results[:max_drawdown])}
                trend={:down}
              />
              <.stat
                label="WIN RATE"
                value={format_pct(@results[:win_rate])}
              />
            </div>

            <!-- Equity Curve Chart -->
            <div class="border border-green-500/20 bg-black p-4">
              <div class="text-xs text-green-500/50 mb-2">[EQUITY CURVE]</div>
              <pre class="text-green-400 text-xs leading-tight"><%= render_equity_chart(@equity_curve) %></pre>
            </div>

            <!-- Trade Statistics -->
            <div class="grid grid-cols-2 gap-4">
              <div class="space-y-2 text-sm">
                <div class="text-green-500/50">[TRADE STATS]</div>
                <div class="flex justify-between">
                  <span>Total Trades:</span>
                  <span class="text-amber-400"><%= @results[:total_trades] || @results[:positions_held] || 0 %></span>
                </div>
                <div class="flex justify-between">
                  <span>Winning Trades:</span>
                  <span class="text-green-400"><%= @results[:winning_trades] || 0 %></span>
                </div>
                <div class="flex justify-between">
                  <span>Losing Trades:</span>
                  <span class="text-red-400"><%= @results[:losing_trades] || 0 %></span>
                </div>
              </div>

              <div class="space-y-2 text-sm">
                <div class="text-green-500/50">[P&L BREAKDOWN]</div>
                <div class="flex justify-between">
                  <span>Gross Profit:</span>
                  <span class="text-green-400">$<%= format_decimal(@results[:gross_profit]) %></span>
                </div>
                <div class="flex justify-between">
                  <span>Net Profit:</span>
                  <span class="text-amber-400">$<%= format_decimal(@results[:net_profit] || @results[:theoretical_profit]) %></span>
                </div>
                <div class="flex justify-between">
                  <span>Cost Impact:</span>
                  <span class="text-red-400">$<%= format_decimal(@results[:total_cost_impact]) %></span>
                </div>
              </div>
            </div>

            <!-- Strategy-specific stats -->
            <div :if={@results[:opportunities_found]} class="border-t border-green-500/20 pt-4">
              <div class="text-xs text-green-500/50 mb-2">[GABAGOOL STATS]</div>
              <div class="grid grid-cols-3 gap-4 text-sm">
                <div class="flex justify-between">
                  <span>Opportunities:</span>
                  <span class="text-amber-400"><%= @results[:opportunities_found] %></span>
                </div>
                <div class="flex justify-between">
                  <span>Avg Spread:</span>
                  <span class="text-amber-400"><%= format_pct(@results[:avg_spread]) %></span>
                </div>
                <div class="flex justify-between">
                  <span>Total Invested:</span>
                  <span class="text-amber-400">$<%= format_decimal(@results[:total_invested]) %></span>
                </div>
              </div>
            </div>
          </div>
        </.panel>
      </div>
    </div>
    """
  end

  # Helpers

  defp format_pct(nil), do: "--%"
  defp format_pct(pct) when is_number(pct), do: "#{:erlang.float_to_binary(pct * 1.0, decimals: 2)}%"

  defp format_decimal(nil), do: "0.00"
  defp format_decimal(num), do: :erlang.float_to_binary(num * 1.0, decimals: 4)

  defp return_trend(ret) when ret > 0, do: :up
  defp return_trend(ret) when ret < 0, do: :down
  defp return_trend(_), do: nil

  defp sharpe_trend(nil), do: nil
  defp sharpe_trend(s) when s > 1.0, do: :up
  defp sharpe_trend(s) when s < 0, do: :down
  defp sharpe_trend(_), do: nil

  defp render_equity_chart([]), do: "NO DATA"

  defp render_equity_chart(equity_curve) when length(equity_curve) < 2 do
    "INSUFFICIENT DATA POINTS"
  end

  defp render_equity_chart(equity_curve) do
    # Normalize and sample the equity curve
    values = equity_curve |> Enum.reverse() |> Enum.take(50)
    min_val = Enum.min(values)
    max_val = Enum.max(values)
    range = max(max_val - min_val, 0.001)
    height = 8

    lines =
      for row <- (height - 1)..0 do
        threshold = min_val + (range * (row / height))
        label = :erlang.float_to_binary(threshold, decimals: 0) |> String.pad_leading(8)

        chars =
          values
          |> Enum.map(fn val ->
            if val >= threshold, do: "#", else: " "
          end)
          |> Enum.join("")

        "#{label} |#{chars}"
      end

    x_axis = "         +" <> String.duplicate("-", length(values))
    time_label = "         " <> String.pad_leading("START", div(length(values), 2)) <> String.pad_leading("END", div(length(values), 2))

    Enum.join(lines ++ [x_axis, time_label], "\n")
  end
end
