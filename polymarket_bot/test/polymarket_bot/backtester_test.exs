defmodule PolymarketBot.BacktesterTest do
  use ExUnit.Case

  alias PolymarketBot.Backtester
  alias PolymarketBot.Backtester.Strategies.{MeanReversion, Momentum}

  describe "run/1 validation" do
    test "requires market_id" do
      result = Backtester.run(strategy: MeanReversion)

      assert result == {:error, "Missing required option: market_id"}
    end

    test "requires strategy" do
      result = Backtester.run(market_id: "test-market")

      assert result == {:error, "Missing required option: strategy"}
    end
  end

  describe "available strategies" do
    test "MeanReversion has required callbacks" do
      assert function_exported?(MeanReversion, :init, 1)
      assert function_exported?(MeanReversion, :on_price, 2)
      assert function_exported?(MeanReversion, :name, 0)
      assert function_exported?(MeanReversion, :default_config, 0)
    end

    test "Momentum has required callbacks" do
      assert function_exported?(Momentum, :init, 1)
      assert function_exported?(Momentum, :on_price, 2)
      assert function_exported?(Momentum, :name, 0)
      assert function_exported?(Momentum, :default_config, 0)
    end
  end

  # Integration tests that require database
  # Run with: mix test --include database
  @moduletag :database

  describe "run/1 with database" do
    @describetag :skip

    test "runs backtest against real data" do
      # This test requires actual data in the database
      # Skip in CI, run manually with: mix test --include database

      result =
        Backtester.run(
          market_id: "some-real-market-id",
          strategy: MeanReversion,
          strategy_config: %{window_size: 10, threshold: 0.03}
        )

      case result do
        {:ok, results} ->
          assert results.strategy_name == "Mean Reversion"
          assert is_map(results.metrics)
          assert is_list(results.trades)

        {:error, "No data found" <> _} ->
          # Expected if no data in test DB
          :ok
      end
    end
  end
end
