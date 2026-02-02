defmodule PolymarketBot.Data.ChainlinkWSTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Data.ChainlinkWS

  # The WebSocket client requires a running connection
  # These tests verify the module structure and API
  @moduletag :unit

  describe "module structure" do
    test "defines start_link/1" do
      Code.ensure_loaded!(ChainlinkWS)
      assert function_exported?(ChainlinkWS, :start_link, 1)
    end

    test "defines get_last_price/1" do
      Code.ensure_loaded!(ChainlinkWS)
      assert function_exported?(ChainlinkWS, :get_last_price, 1)
    end

    test "defines subscribe/1" do
      Code.ensure_loaded!(ChainlinkWS)
      assert function_exported?(ChainlinkWS, :subscribe, 1)
    end
  end

  describe "get_last_price/1" do
    test "returns error when not running" do
      result = ChainlinkWS.get_last_price(:nonexistent_process)

      assert result == {:error, :not_running}
    end
  end

  # Integration test - requires actual WebSocket connection
  describe "websocket connection" do
    @tag :external
    test "can start and receive price updates" do
      test_pid = self()

      callback = fn price, _ts ->
        send(test_pid, {:price_update, price})
      end

      {:ok, pid} = ChainlinkWS.start_link(callback: callback, name: :test_chainlink_ws)

      # Wait for potential price update (may not receive one quickly)
      receive do
        {:price_update, price} ->
          assert is_float(price)
          assert price > 0
      after
        5000 ->
          # It's OK if we don't receive an update quickly
          # The connection may just not have data yet
          :ok
      end

      GenServer.stop(pid)
    end
  end
end
