defmodule PolymarketBot.Backtester.MetricsTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Backtester.Metrics

  describe "calculate/1" do
    test "returns empty metrics for empty trades" do
      metrics = Metrics.calculate([])

      assert metrics.total_trades == 0
      assert metrics.total_return == 0.0
      assert metrics.win_rate == 0.0
    end

    test "calculates metrics for winning trades" do
      trades = [
        %{entry_price: 0.50, exit_price: 0.60, return: 0.20},
        %{entry_price: 0.55, exit_price: 0.66, return: 0.20}
      ]

      metrics = Metrics.calculate(trades)

      assert metrics.total_trades == 2
      assert metrics.winning_trades == 2
      assert metrics.losing_trades == 0
      assert metrics.win_rate == 1.0
      assert_in_delta metrics.avg_win, 0.20, 0.001
      assert metrics.avg_loss == 0.0
    end

    test "calculates metrics for mixed trades" do
      trades = [
        %{entry_price: 0.50, exit_price: 0.55, return: 0.10},
        %{entry_price: 0.55, exit_price: 0.50, return: -0.09},
        %{entry_price: 0.50, exit_price: 0.60, return: 0.20}
      ]

      metrics = Metrics.calculate(trades)

      assert metrics.total_trades == 3
      assert metrics.winning_trades == 2
      assert metrics.losing_trades == 1
      assert_in_delta metrics.win_rate, 0.666, 0.01
    end
  end

  describe "total_return/1" do
    test "calculates compounded return" do
      trades = [
        %{return: 0.10},
        %{return: 0.10},
        %{return: 0.10}
      ]

      total = Metrics.total_return(trades)

      # 1.1 * 1.1 * 1.1 - 1 = 0.331
      assert_in_delta total, 0.331, 0.001
    end

    test "handles losses" do
      trades = [
        %{return: 0.10},
        %{return: -0.20}
      ]

      total = Metrics.total_return(trades)

      # 1.1 * 0.8 - 1 = -0.12
      assert_in_delta total, -0.12, 0.001
    end
  end

  describe "max_drawdown/1" do
    test "calculates max drawdown from peak" do
      trades = [
        %{return: 0.20},
        %{return: -0.30},
        %{return: 0.10}
      ]

      dd = Metrics.max_drawdown(trades)

      # Peak is 1.2, then drops to 0.84 (-0.30)
      # Drawdown = (1.2 - 0.84) / 1.2 = 0.30
      assert_in_delta dd, 0.30, 0.01
    end

    test "returns 0 for no drawdown" do
      trades = [
        %{return: 0.10},
        %{return: 0.10}
      ]

      dd = Metrics.max_drawdown(trades)
      assert dd == 0.0
    end
  end

  describe "profit_factor/1" do
    test "calculates ratio of wins to losses" do
      trades = [
        %{return: 0.20},
        %{return: -0.10}
      ]

      pf = Metrics.profit_factor(trades)

      # 0.20 / 0.10 = 2.0
      assert_in_delta pf, 2.0, 0.001
    end

    test "returns large number when no losses" do
      trades = [
        %{return: 0.10},
        %{return: 0.20}
      ]

      pf = Metrics.profit_factor(trades)
      assert pf == 999.99
    end
  end

  describe "sharpe_ratio/1" do
    test "calculates sharpe ratio" do
      trades = [
        %{return: 0.05},
        %{return: 0.03},
        %{return: 0.04},
        %{return: 0.06},
        %{return: 0.02}
      ]

      sharpe = Metrics.sharpe_ratio(trades, 0.0)

      # Should be positive with consistent small wins
      assert sharpe > 0
    end

    test "returns 0 for insufficient data" do
      trades = [%{return: 0.10}]
      assert Metrics.sharpe_ratio(trades) == 0.0
    end
  end

  describe "expectancy/1" do
    test "calculates expected value per trade" do
      trades = [
        %{return: 0.10},
        %{return: 0.10},
        %{return: -0.05}
      ]

      exp = Metrics.expectancy(trades)

      # win_rate = 2/3
      # avg_win = 0.10
      # avg_loss = 0.05
      # expectancy = (2/3 * 0.10) - (1/3 * 0.05) = 0.0667 - 0.0167 = 0.05
      assert_in_delta exp, 0.05, 0.01
    end
  end
end
