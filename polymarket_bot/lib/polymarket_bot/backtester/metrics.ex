defmodule PolymarketBot.Backtester.Metrics do
  @moduledoc """
  Calculates performance metrics for backtest results.

  Metrics include:
  - Total return
  - Win rate
  - Average win/loss
  - Max drawdown
  - Sharpe ratio (if risk-free rate provided)
  - Profit factor
  """

  @doc """
  Calculate all metrics from a list of trades.

  Each trade should be a map with at least:
  - `:return` - The return percentage of the trade
  - `:entry_price` - Entry price
  - `:exit_price` - Exit price
  """
  def calculate(trades, opts \\ []) do
    if Enum.empty?(trades) do
      empty_metrics()
    else
      %{
        total_trades: length(trades),
        total_return: total_return(trades),
        win_rate: win_rate(trades),
        avg_win: avg_win(trades),
        avg_loss: avg_loss(trades),
        max_drawdown: max_drawdown(trades),
        profit_factor: profit_factor(trades),
        sharpe_ratio: sharpe_ratio(trades, opts[:risk_free_rate] || 0.0),
        expectancy: expectancy(trades),
        best_trade: best_trade(trades),
        worst_trade: worst_trade(trades),
        winning_trades: count_wins(trades),
        losing_trades: count_losses(trades)
      }
    end
  end

  @doc """
  Returns empty metrics structure when no trades occurred.
  """
  def empty_metrics do
    %{
      total_trades: 0,
      total_return: 0.0,
      win_rate: 0.0,
      avg_win: 0.0,
      avg_loss: 0.0,
      max_drawdown: 0.0,
      profit_factor: 0.0,
      sharpe_ratio: 0.0,
      expectancy: 0.0,
      best_trade: nil,
      worst_trade: nil,
      winning_trades: 0,
      losing_trades: 0
    }
  end

  @doc """
  Calculate total compounded return from a sequence of trades.
  """
  def total_return(trades) do
    trades
    |> Enum.reduce(1.0, fn trade, acc -> acc * (1 + get_return(trade)) end)
    |> Kernel.-(1.0)
  end

  @doc """
  Calculate win rate (percentage of profitable trades).
  """
  def win_rate(trades) do
    total = length(trades)

    if total == 0 do
      0.0
    else
      wins = count_wins(trades)
      wins / total
    end
  end

  @doc """
  Calculate average winning trade return.
  """
  def avg_win(trades) do
    wins = Enum.filter(trades, &(get_return(&1) > 0))

    if Enum.empty?(wins) do
      0.0
    else
      wins |> Enum.map(&get_return/1) |> Enum.sum() |> Kernel./(length(wins))
    end
  end

  @doc """
  Calculate average losing trade return (will be negative).
  """
  def avg_loss(trades) do
    losses = Enum.filter(trades, &(get_return(&1) < 0))

    if Enum.empty?(losses) do
      0.0
    else
      losses |> Enum.map(&get_return/1) |> Enum.sum() |> Kernel./(length(losses))
    end
  end

  @doc """
  Calculate maximum drawdown from peak equity.
  """
  def max_drawdown(trades) do
    {_equity, _peak, max_dd} =
      trades
      |> Enum.reduce({1.0, 1.0, 0.0}, fn trade, {equity, peak, max_dd} ->
        new_equity = equity * (1 + get_return(trade))
        new_peak = max(peak, new_equity)
        drawdown = if new_peak > 0, do: (new_peak - new_equity) / new_peak, else: 0.0
        new_max_dd = max(max_dd, drawdown)
        {new_equity, new_peak, new_max_dd}
      end)

    max_dd
  end

  @doc """
  Calculate profit factor (gross profits / gross losses).
  """
  def profit_factor(trades) do
    gross_profit =
      trades
      |> Enum.filter(&(get_return(&1) > 0))
      |> Enum.map(&get_return/1)
      |> Enum.sum()

    gross_loss =
      trades
      |> Enum.filter(&(get_return(&1) < 0))
      |> Enum.map(&get_return/1)
      |> Enum.map(&abs/1)
      |> Enum.sum()

    if gross_loss > 0 do
      gross_profit / gross_loss
    else
      # No losses = infinite profit factor, represent as large number
      if gross_profit > 0, do: 999.99, else: 0.0
    end
  end

  @doc """
  Calculate Sharpe ratio (risk-adjusted return).

  Sharpe = (avg_return - risk_free_rate) / std_dev_of_returns
  """
  def sharpe_ratio(trades, risk_free_rate \\ 0.0) do
    returns = Enum.map(trades, &get_return/1)
    n = length(returns)

    if n < 2 do
      0.0
    else
      avg_return = Enum.sum(returns) / n
      excess_return = avg_return - risk_free_rate

      variance =
        returns
        |> Enum.map(fn r -> :math.pow(r - avg_return, 2) end)
        |> Enum.sum()
        |> Kernel./(n - 1)

      std_dev = :math.sqrt(variance)

      if std_dev > 0 do
        excess_return / std_dev
      else
        0.0
      end
    end
  end

  @doc """
  Calculate expectancy (expected value per trade).

  Expectancy = (win_rate * avg_win) - (loss_rate * avg_loss)
  """
  def expectancy(trades) do
    wr = win_rate(trades)
    aw = avg_win(trades)
    al = abs(avg_loss(trades))

    wr * aw - (1 - wr) * al
  end

  @doc """
  Find the best trade.
  """
  def best_trade(trades) do
    Enum.max_by(trades, &get_return/1, fn -> nil end)
  end

  @doc """
  Find the worst trade.
  """
  def worst_trade(trades) do
    Enum.min_by(trades, &get_return/1, fn -> nil end)
  end

  # Private helpers

  defp get_return(%{return: r}) when is_number(r), do: r
  defp get_return(_), do: 0.0

  defp count_wins(trades), do: Enum.count(trades, &(get_return(&1) > 0))
  defp count_losses(trades), do: Enum.count(trades, &(get_return(&1) < 0))
end
