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
  """

  require Logger
  import Ecto.Query

  alias PolymarketBot.Repo
  alias PolymarketBot.Schema.PriceSnapshot
  alias PolymarketBot.Backtester.{Metrics, Report}

  @type backtest_opts :: [
          market_id: String.t(),
          strategy: module(),
          strategy_config: map(),
          start_date: DateTime.t() | nil,
          end_date: DateTime.t() | nil,
          initial_capital: float()
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
      {:ok,
       %{
         market_id: market_id,
         strategy: strategy,
         strategy_config: opts[:strategy_config] || %{},
         start_date: opts[:start_date],
         end_date: opts[:end_date],
         initial_capital: opts[:initial_capital] || 1000.0
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

    # Initialize strategy
    with {:ok, strategy_state} <- config.strategy.init(config.strategy_config) do
      # Run through all price data
      # equity_state: {equity_list, position, entry_price, position_size}
      initial_equity_state = {[config.initial_capital], nil, nil, 0.0}

      {final_state, signals, equity_state} =
        data
        |> Enum.reduce({strategy_state, [], initial_equity_state}, fn snapshot,
                                                                       {state, signals,
                                                                        equity_state} ->
          price_data = %{
            timestamp: snapshot.timestamp,
            yes_price: snapshot.yes_price,
            no_price: snapshot.no_price,
            volume: snapshot.volume,
            liquidity: snapshot.liquidity
          }

          {signal, new_state} = config.strategy.on_price(price_data, state)

          # Track equity changes based on signals
          new_equity_state = update_equity(equity_state, signal, snapshot.yes_price)

          {new_state, [{signal, price_data} | signals], new_equity_state}
        end)

      {equity_curve, _, _, _} = equity_state

      # Get strategy completion stats
      strategy_stats =
        if function_exported?(config.strategy, :on_complete, 1) do
          case config.strategy.on_complete(final_state) do
            {:ok, stats} -> stats
            _ -> %{}
          end
        else
          %{}
        end

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
        final_capital: List.last(equity_curve),
        metrics: metrics,
        trades: trades,
        equity_curve: Enum.reverse(equity_curve),
        strategy_stats: strategy_stats
      }

      {:ok, results}
    end
  end

  defp update_equity({equity, position, entry_price, position_size}, signal, price) do
    current = List.first(equity)

    case signal do
      {:buy, size} when is_nil(position) ->
        # Enter long position - equity stays the same, we now hold the position
        {[current | equity], :long, price, size}

      {:sell, _size} when position == :long ->
        # Exit position, calculate realized P&L
        pnl = (price - entry_price) / entry_price * (current * position_size)
        new_equity = current + pnl
        {[new_equity | equity], nil, nil, 0.0}

      _ ->
        # Hold - track unrealized P&L if in position
        if position == :long do
          unrealized_pnl = (price - entry_price) / entry_price * (current * position_size)
          {[current + unrealized_pnl | equity], position, entry_price, position_size}
        else
          {[current | equity], position, entry_price, position_size}
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
