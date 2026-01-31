defmodule PolymarketBot.Backtester.Report do
  @moduledoc """
  Generates reports from backtest results.

  Supports multiple output formats:
  - Text (console/file)
  - JSON
  - Markdown
  """

  alias PolymarketBot.Backtester.Metrics

  @doc """
  Generate a report from backtest results.

  Options:
  - `:format` - Output format: `:text`, `:json`, or `:markdown` (default: `:text`)
  - `:output` - Output path (if nil, returns string)
  """
  def generate(results, opts \\ []) do
    format = opts[:format] || :text
    output = opts[:output]

    content =
      case format do
        :text -> format_text(results)
        :json -> format_json(results)
        :markdown -> format_markdown(results)
        _ -> format_text(results)
      end

    if output do
      File.write!(output, content)
      {:ok, output}
    else
      {:ok, content}
    end
  end

  @doc """
  Generate and save report to the default reports directory.

  Options:
  - `:format` - Output format (default: `:markdown`)
  - `:output_dir` - Base directory for reports (default: current working directory)
  """
  def save(results, name, opts \\ []) do
    format = opts[:format] || :markdown
    ext = format_extension(format)

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0, 15)
    filename = "#{name}_#{timestamp}.#{ext}"

    # Ensure reports directory exists
    base_dir = opts[:output_dir] || File.cwd!()
    reports_dir = Path.join([base_dir, "reports"])
    File.mkdir_p!(reports_dir)

    path = Path.join(reports_dir, filename)
    generate(results, Keyword.merge(opts, output: path, format: format))
  end

  # Text format
  defp format_text(results) do
    metrics = results[:metrics] || Metrics.empty_metrics()

    """
    ================================================================================
    BACKTEST REPORT
    ================================================================================

    Strategy: #{results[:strategy_name] || "Unknown"}
    Market: #{results[:market_id] || "Unknown"}
    Period: #{format_date(results[:start_date])} to #{format_date(results[:end_date])}
    Data Points: #{results[:data_points] || 0}

    --------------------------------------------------------------------------------
    PERFORMANCE METRICS
    --------------------------------------------------------------------------------

    Total Return:      #{format_percent(metrics.total_return)}
    Win Rate:          #{format_percent(metrics.win_rate)} (#{metrics.winning_trades}/#{metrics.total_trades})
    Max Drawdown:      #{format_percent(metrics.max_drawdown)}

    Average Win:       #{format_percent(metrics.avg_win)}
    Average Loss:      #{format_percent(metrics.avg_loss)}
    Profit Factor:     #{format_number(metrics.profit_factor)}

    Sharpe Ratio:      #{format_number(metrics.sharpe_ratio)}
    Expectancy:        #{format_percent(metrics.expectancy)}

    --------------------------------------------------------------------------------
    TRADE SUMMARY
    --------------------------------------------------------------------------------

    Total Trades:      #{metrics.total_trades}
    Winning Trades:    #{metrics.winning_trades}
    Losing Trades:     #{metrics.losing_trades}

    Best Trade:        #{format_trade_return(metrics.best_trade)}
    Worst Trade:       #{format_trade_return(metrics.worst_trade)}

    ================================================================================
    """
  end

  # JSON format
  defp format_json(results) do
    results
    |> prepare_for_json()
    |> Jason.encode!(pretty: true)
  end

  # Markdown format
  defp format_markdown(results) do
    metrics = results[:metrics] || Metrics.empty_metrics()

    """
    # Backtest Report

    ## Overview

    | Parameter | Value |
    |-----------|-------|
    | Strategy | #{results[:strategy_name] || "Unknown"} |
    | Market | #{results[:market_id] || "Unknown"} |
    | Period | #{format_date(results[:start_date])} to #{format_date(results[:end_date])} |
    | Data Points | #{results[:data_points] || 0} |

    ## Performance Metrics

    | Metric | Value |
    |--------|-------|
    | Total Return | #{format_percent(metrics.total_return)} |
    | Win Rate | #{format_percent(metrics.win_rate)} |
    | Max Drawdown | #{format_percent(metrics.max_drawdown)} |
    | Average Win | #{format_percent(metrics.avg_win)} |
    | Average Loss | #{format_percent(metrics.avg_loss)} |
    | Profit Factor | #{format_number(metrics.profit_factor)} |
    | Sharpe Ratio | #{format_number(metrics.sharpe_ratio)} |
    | Expectancy | #{format_percent(metrics.expectancy)} |

    ## Trade Summary

    | Statistic | Value |
    |-----------|-------|
    | Total Trades | #{metrics.total_trades} |
    | Winning Trades | #{metrics.winning_trades} |
    | Losing Trades | #{metrics.losing_trades} |
    | Best Trade | #{format_trade_return(metrics.best_trade)} |
    | Worst Trade | #{format_trade_return(metrics.worst_trade)} |

    #{format_trade_list(results[:trades])}

    ---
    *Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}*
    """
  end

  # Helpers

  defp format_extension(:text), do: "txt"
  defp format_extension(:json), do: "json"
  defp format_extension(:markdown), do: "md"
  defp format_extension(_), do: "txt"

  defp format_percent(nil), do: "N/A"
  defp format_percent(val) when is_number(val), do: "#{Float.round(val * 100, 2)}%"
  defp format_percent(_), do: "N/A"

  defp format_number(nil), do: "N/A"
  defp format_number(val) when is_number(val), do: Float.round(val * 1.0, 4) |> to_string()
  defp format_number(_), do: "N/A"

  defp format_date(nil), do: "N/A"
  defp format_date(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_date(date), do: to_string(date)

  defp format_trade_return(nil), do: "N/A"
  defp format_trade_return(%{return: r}), do: format_percent(r)
  defp format_trade_return(_), do: "N/A"

  defp format_trade_list(nil), do: ""
  defp format_trade_list([]), do: ""

  defp format_trade_list(trades) when length(trades) > 0 do
    header = """
    ## Trade History

    | # | Entry | Exit | Return |
    |---|-------|------|--------|
    """

    rows =
      trades
      |> Enum.take(50)
      |> Enum.with_index(1)
      |> Enum.map(fn {trade, idx} ->
        "| #{idx} | #{format_price(trade[:entry_price])} | #{format_price(trade[:exit_price])} | #{format_percent(trade[:return])} |"
      end)
      |> Enum.join("\n")

    more =
      if length(trades) > 50 do
        "\n\n*Showing first 50 of #{length(trades)} trades*"
      else
        ""
      end

    header <> rows <> more
  end

  defp format_price(nil), do: "N/A"
  defp format_price(p) when is_number(p), do: Float.round(p * 1.0, 4) |> to_string()
  defp format_price(_), do: "N/A"

  defp prepare_for_json(results) do
    results
    |> Map.new(fn
      {:start_date, %DateTime{} = dt} -> {:start_date, DateTime.to_iso8601(dt)}
      {:end_date, %DateTime{} = dt} -> {:end_date, DateTime.to_iso8601(dt)}
      {:trades, trades} -> {:trades, Enum.map(trades, &prepare_trade_for_json/1)}
      {k, v} -> {k, v}
    end)
  end

  defp prepare_trade_for_json(trade) do
    Map.new(trade, fn
      {:timestamp, %DateTime{} = dt} -> {:timestamp, DateTime.to_iso8601(dt)}
      {k, v} -> {k, v}
    end)
  end
end
