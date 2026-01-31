defmodule PolymarketBot.Backtester.ReportTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Backtester.Report
  alias PolymarketBot.Backtester.Metrics

  @sample_results %{
    market_id: "test-market-123",
    strategy_name: "Test Strategy",
    strategy_config: %{window_size: 20},
    start_date: ~U[2024-01-01 00:00:00Z],
    end_date: ~U[2024-01-31 23:59:59Z],
    data_points: 1000,
    initial_capital: 1000.0,
    final_capital: 1150.0,
    metrics: %{
      total_trades: 10,
      total_return: 0.15,
      win_rate: 0.6,
      avg_win: 0.08,
      avg_loss: -0.05,
      max_drawdown: 0.12,
      profit_factor: 1.8,
      sharpe_ratio: 1.2,
      expectancy: 0.028,
      winning_trades: 6,
      losing_trades: 4,
      best_trade: %{return: 0.15},
      worst_trade: %{return: -0.08}
    },
    trades: [
      %{entry_price: 0.50, exit_price: 0.55, return: 0.10},
      %{entry_price: 0.52, exit_price: 0.48, return: -0.08}
    ]
  }

  describe "generate/2" do
    test "generates text format" do
      {:ok, content} = Report.generate(@sample_results, format: :text)

      assert content =~ "BACKTEST REPORT"
      assert content =~ "Test Strategy"
      assert content =~ "test-market-123"
      # total return
      assert content =~ "15.0%"
      # win rate
      assert content =~ "60.0%"
    end

    test "generates json format" do
      {:ok, content} = Report.generate(@sample_results, format: :json)

      decoded = Jason.decode!(content)

      assert decoded["market_id"] == "test-market-123"
      assert decoded["strategy_name"] == "Test Strategy"
      assert decoded["metrics"]["total_return"] == 0.15
    end

    test "generates markdown format" do
      {:ok, content} = Report.generate(@sample_results, format: :markdown)

      assert content =~ "# Backtest Report"
      assert content =~ "| Strategy | Test Strategy |"
      assert content =~ "| Total Return | 15.0% |"
      assert content =~ "## Trade History"
    end

    test "writes to file when output specified" do
      path = Path.join(System.tmp_dir!(), "test_report_#{:rand.uniform(10000)}.txt")

      try do
        {:ok, ^path} = Report.generate(@sample_results, format: :text, output: path)

        assert File.exists?(path)
        content = File.read!(path)
        assert content =~ "BACKTEST REPORT"
      after
        File.rm(path)
      end
    end
  end

  describe "save/3" do
    test "saves report to reports directory" do
      # Use a temp directory to avoid polluting the project
      original_cwd = File.cwd!()

      tmp_dir = Path.join(System.tmp_dir!(), "polymarket_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(tmp_dir)
      File.cd!(tmp_dir)

      try do
        {:ok, path} = Report.save(@sample_results, "test_backtest", format: :markdown)

        assert File.exists?(path)
        assert String.contains?(path, "test_backtest")
        assert String.ends_with?(path, ".md")
      after
        File.cd!(original_cwd)
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "edge cases" do
    test "handles empty metrics" do
      results = %{
        market_id: "test",
        strategy_name: "Test",
        metrics: Metrics.empty_metrics(),
        trades: []
      }

      {:ok, content} = Report.generate(results, format: :text)

      assert content =~ "Total Trades:      0"
    end

    test "handles nil dates" do
      results = Map.merge(@sample_results, %{start_date: nil, end_date: nil})

      {:ok, content} = Report.generate(results, format: :text)

      assert content =~ "N/A to N/A"
    end
  end
end
