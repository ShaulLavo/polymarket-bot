defmodule PolymarketBot.Backtester do
  @moduledoc """
  Backtesting engine for Polymarket trading strategies.

  The backtester:
  1. Loads historical price data from SQLite
  2. Runs a strategy against the data
  3. Calculates performance metrics
  4. Generates reports

  ## Usage

      # Run a backtest with mean reversion strategy
      {:ok, results} = PolymarketBot.Backtester.run(
        market_id: "some-market-id",
        strategy: PolymarketBot.Backtester.Strategies.MeanReversion,
        strategy_config: %{window_size: 20, threshold: 0.05}
      )

      # Generate a report
      {:ok, path} = PolymarketBot.Backtester.Report.save(results, "mean_reversion_test")

  ## Options

  - `:market_id` - The Polymarket market ID to backtest (required)
  - `:strategy` - The strategy module implementing the Strategy behaviour (required)
  - `:strategy_config` - Configuration map for the strategy (optional)
  - `:start_date` - Start of backtest period (optional, defaults to earliest data)
  - `:end_date` - End of backtest period (optional, defaults to latest data)
  - `:initial_capital` - Starting capital (default: 1000.0)
  - `:trading_costs` - Trading costs configuration (optional, see TradingCosts module)
  - `:multi_position` - Enable multi-position tracking (default: false)

  ## Trading Costs

  Enable realistic cost simulation:

      {:ok, results} = PolymarketBot.Backtester.run(
        market_id: "btc-15m-xxx",
        strategy: PolymarketBot.Backtester.Strategies.GabagoolArb,
        trading_costs: %{
          slippage_factor: 0.001,      # 0.1% base slippage
          spread_enabled: true,         # Model bid-ask spread
          default_spread: 0.01          # 1 cent default spread
        }
      )
  """

  require Logger
  import Ecto.Query

  alias PolymarketBot.Repo
  alias PolymarketBot.Schema.PriceSnapshot
  alias PolymarketBot.Backtester.{Metrics, Report, TradingCosts, PositionManager}

  @type backtest_opts :: [
          market_id: String.t(),
          strategy: module(),
          strategy_config: map(),
          start_date: DateTime.t() | nil,
          end_date: DateTime.t() | nil,
          initial_capital: float(),
          trading_costs: map() | nil,
          multi_position: boolean()
        ]

  @doc """
  Run a backtest with the given options.

  Returns {:ok, results} or {:error, reason}.
  """
  @spec run(backtest_opts()) :: {:ok, map()} | {:error, term()}
  def run(opts) do
    with {:ok, config} <- validate_opts(opts),
         {:ok, data} <- load_data(config),
         {:ok, results} <- execute_backtest(data, config) do
      {:ok, results}
    end
  end

  @doc """
  Run a backtest and save a report.

  Returns {:ok, report_path} or {:error, reason}.
  """
  @spec run_and_report(backtest_opts(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run_and_report(opts, report_opts \\ []) do
    with {:ok, results} <- run(opts) do
      name = report_opts[:name] || "backtest"
      Report.save(results, name, report_opts)
    end
  end

  @doc """
  List available markets with historical data.
  """
  def list_available_markets do
    query =
      from(p in PriceSnapshot,
        group_by: p.market_id,
        select: %{
          market_id: p.market_id,
          data_points: count(p.id),
          first_snapshot: min(p.timestamp),
          last_snapshot: max(p.timestamp)
        },
        order_by: [desc: count(p.id)]
      )

    Repo.all(query)
  end

  @doc """
  Get summary statistics for a market's historical data.
  """
  def market_stats(market_id) do
    query =
      from(p in PriceSnapshot,
        where: p.market_id == ^market_id,
        select: %{
          data_points: count(p.id),
          first_snapshot: min(p.timestamp),
          last_snapshot: max(p.timestamp),
          avg_yes_price: avg(p.yes_price),
          min_yes_price: min(p.yes_price),
          max_yes_price: max(p.yes_price)
        }
      )

    Repo.one(query)
  end

  # Private functions

  defp validate_opts(opts) do
    with {:ok, market_id} <- get_required(opts, :market_id),
         {:ok, strategy} <- get_required(opts, :strategy) do
      trading_costs =
        case opts[:trading_costs] do
          nil -> nil
          config when is_map(config) -> TradingCosts.merge_config(config)
        end

      {:ok,
       %{
         market_id: market_id,
         strategy: strategy,
         strategy_config: opts[:strategy_config] || %{},
         start_date: opts[:start_date],
         end_date: opts[:end_date],
         initial_capital: opts[:initial_capital] || 1000.0,
         trading_costs: trading_costs,
         multi_position: opts[:multi_position] || false
       }}
    end
  end

  defp get_required(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, "Missing required option: #{key}"}
      value -> {:ok, value}
    end
  end

  defp load_data(config) do
    Logger.info("Loading historical data for market #{config.market_id}...")

    query =
      from(p in PriceSnapshot,
        where: p.market_id == ^config.market_id,
        order_by: [asc: p.timestamp]
      )

    query =
      if config.start_date do
        from(p in query, where: p.timestamp >= ^config.start_date)
      else
        query
      end

    query =
      if config.end_date do
        from(p in query, where: p.timestamp <= ^config.end_date)
      else
        query
      end

    data = Repo.all(query)

    if Enum.empty?(data) do
      {:error, "No data found for market #{config.market_id}"}
    else
      Logger.info("Loaded #{length(data)} price snapshots")
      {:ok, data}
    end
  end

  defp execute_backtest(data, config) do
    Logger.info("Running backtest with #{config.strategy}...")

    if config.multi_position do
      execute_backtest_multi_position(data, config)
    else
      execute_backtest_legacy(data, config)
    end
  end

  # Multi-position backtest using PositionManager
  defp execute_backtest_multi_position(data, config) do
    with {:ok, strategy_state} <- config.strategy.init(config.strategy_config) do
      initial_pm_state = PositionManager.init(config.initial_capital)

      {final_state, signals, pm_state} =
        data
        |> Enum.reduce({strategy_state, [], initial_pm_state}, fn snapshot,
                                                                  {state, signals, pm_state} ->
          # Build enhanced price_data with cost info
          price_data = build_price_data(snapshot, config)

          {signal, new_state} = config.strategy.on_price(price_data, state)

          # Process signal through position manager
          new_pm_state = process_signal_multi(pm_state, signal, price_data, config)

          {new_state, [{signal, price_data} | signals], new_pm_state}
        end)

      # Get strategy completion stats
      strategy_stats = get_strategy_stats(config.strategy, final_state)

      trades = strategy_stats[:trades] || extract_trades(Enum.reverse(signals))

      # Calculate metrics
      metrics = Metrics.calculate(trades)

      # Get final equity from position manager
      final_capital = PositionManager.get_total_equity(pm_state)
      equity_curve = Enum.reverse(pm_state.equity_curve)

      # Build results with cost analysis
      results = %{
        market_id: config.market_id,
        strategy_name: config.strategy.name(),
        strategy_config: config.strategy_config,
        start_date: List.first(data).timestamp,
        end_date: List.last(data).timestamp,
        data_points: length(data),
        initial_capital: config.initial_capital,
        final_capital: final_capital,
        metrics: metrics,
        trades: trades,
        equity_curve: equity_curve,
        strategy_stats: strategy_stats,
        position_summary: PositionManager.get_summary(pm_state),
        trading_costs_enabled: config.trading_costs != nil
      }

      {:ok, results}
    end
  end

  # Legacy single-position backtest (maintains backwards compatibility)
  defp execute_backtest_legacy(data, config) do
    with {:ok, strategy_state} <- config.strategy.init(config.strategy_config) do
      # Run through all price data
      # equity_state: {equity_list, position, entry_price, position_size, capital_at_entry}
      initial_equity_state = {[config.initial_capital], nil, nil, 0.0, nil}

      {final_state, signals, equity_state} =
        data
        |> Enum.reduce({strategy_state, [], initial_equity_state}, fn snapshot,
                                                                      {state, signals,
                                                                       equity_state} ->
          price_data = build_price_data(snapshot, config)

          {signal, new_state} = config.strategy.on_price(price_data, state)

          # Track equity changes based on signals (with optional costs)
          new_equity_state = update_equity(equity_state, signal, snapshot.yes_price, config)

          {new_state, [{signal, price_data} | signals], new_equity_state}
        end)

      {equity_curve, _, _, _, _} = equity_state

      # Get strategy completion stats
      strategy_stats = get_strategy_stats(config.strategy, final_state)

      trades = strategy_stats[:trades] || extract_trades(Enum.reverse(signals))

      # Calculate metrics
      metrics = Metrics.calculate(trades)

      # Build results
      results = %{
        market_id: config.market_id,
        strategy_name: config.strategy.name(),
        strategy_config: config.strategy_config,
        start_date: List.first(data).timestamp,
        end_date: List.last(data).timestamp,
        data_points: length(data),
        initial_capital: config.initial_capital,
        final_capital: List.first(equity_curve),
        metrics: metrics,
        trades: trades,
        equity_curve: Enum.reverse(equity_curve),
        strategy_stats: strategy_stats,
        trading_costs_enabled: config.trading_costs != nil
      }

      {:ok, results}
    end
  end

  defp build_price_data(snapshot, config) do
    base_data = %{
      timestamp: snapshot.timestamp,
      yes_price: snapshot.yes_price,
      no_price: snapshot.no_price,
      volume: snapshot.volume,
      liquidity: snapshot.liquidity
    }

    # Add trading costs config so strategies can estimate costs
    if config.trading_costs do
      Map.put(base_data, :trading_costs, config.trading_costs)
    else
      base_data
    end
  end

  defp get_strategy_stats(strategy, final_state) do
    if function_exported?(strategy, :on_complete, 1) do
      case strategy.on_complete(final_state) do
        {:ok, stats} -> stats
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp process_signal_multi(pm_state, signal, price_data, config) do
    opts = [
      costs_config: config.trading_costs,
      market_context: %{
        liquidity: price_data.liquidity,
        volume: price_data.volume
      }
    ]

    case signal do
      {:buy, size} ->
        case PositionManager.open_position(
               pm_state,
               :long,
               price_data.yes_price,
               size,
               price_data.timestamp,
               opts
             ) do
          {:ok, new_state, _position} -> new_state
          {:error, _} -> pm_state
        end

      {:open_gabagool, size} ->
        case PositionManager.open_gabagool_position(
               pm_state,
               price_data.yes_price,
               price_data.no_price,
               size,
               price_data.timestamp,
               opts
             ) do
          {:ok, new_state, _position} -> new_state
          {:error, _} -> pm_state
        end

      {:sell, _size} ->
        # Close most recent position
        case pm_state.positions do
          [position | _] ->
            case PositionManager.close_position(
                   pm_state,
                   position.id,
                   price_data.yes_price,
                   price_data.timestamp,
                   opts
                 ) do
              {:ok, new_state, _} -> new_state
              {:error, _} -> pm_state
            end

          [] ->
            pm_state
        end

      {:close_position, position_id} ->
        case PositionManager.close_position(
               pm_state,
               position_id,
               price_data.yes_price,
               price_data.timestamp,
               opts
             ) do
          {:ok, new_state, _} -> new_state
          {:error, _} -> pm_state
        end

      :close_all ->
        case PositionManager.close_all_positions(
               pm_state,
               price_data.yes_price,
               price_data.timestamp,
               opts
             ) do
          {:ok, new_state, _} -> new_state
          _ -> pm_state
        end

      _ ->
        # :hold or unrecognized - just update unrealized P&L
        PositionManager.update_unrealized_pnl(pm_state, price_data.yes_price,
          yes_price: price_data.yes_price,
          no_price: price_data.no_price
        )
    end
  end

  defp update_equity(
         {equity, position, entry_price, position_size, capital_at_entry},
         signal,
         price,
         config
       ) do
    current = List.first(equity)
    costs_config = config[:trading_costs]

    case signal do
      {:buy, size} when is_nil(position) ->
        # Enter long position - apply costs if configured
        exec_price =
          if costs_config do
            {:ok, p, _} = TradingCosts.apply_costs(price, :buy, size * current, costs_config, %{})
            p
          else
            price
          end

        {[current | equity], :long, exec_price, size, current}

      {:sell, _size} when position == :long ->
        # Exit position - apply costs if configured
        exec_price =
          if costs_config do
            {:ok, p, _} =
              TradingCosts.apply_costs(
                price,
                :sell,
                capital_at_entry * position_size,
                costs_config,
                %{}
              )

            p
          else
            price
          end

        pnl = (exec_price - entry_price) / entry_price * (capital_at_entry * position_size)
        new_equity = capital_at_entry + pnl
        {[new_equity | equity], nil, nil, 0.0, nil}

      _ ->
        # Hold - track unrealized P&L if in position
        if position == :long do
          unrealized_pnl =
            (price - entry_price) / entry_price * (capital_at_entry * position_size)

          {[capital_at_entry + unrealized_pnl | equity], position, entry_price, position_size,
           capital_at_entry}
        else
          {[current | equity], position, entry_price, position_size, capital_at_entry}
        end
    end
  end

  # Extract trades from signals when strategy doesn't provide them
  defp extract_trades(signals) do
    signals
    |> Enum.reduce({nil, []}, fn {signal, price_data}, {pending_entry, trades} ->
      case signal do
        {:buy, _} ->
          {price_data, trades}

        :buy ->
          {price_data, trades}

        {:sell, _} when not is_nil(pending_entry) ->
          trade = %{
            entry_price: pending_entry.yes_price,
            exit_price: price_data.yes_price,
            return: (price_data.yes_price - pending_entry.yes_price) / pending_entry.yes_price,
            timestamp: price_data.timestamp
          }

          {nil, [trade | trades]}

        :sell when not is_nil(pending_entry) ->
          trade = %{
            entry_price: pending_entry.yes_price,
            exit_price: price_data.yes_price,
            return: (price_data.yes_price - pending_entry.yes_price) / pending_entry.yes_price,
            timestamp: price_data.timestamp
          }

          {nil, [trade | trades]}

        _ ->
          {pending_entry, trades}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
