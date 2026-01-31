defmodule PolymarketBot.APITest do
  use ExUnit.Case, async: true

  alias PolymarketBot.API

  @moduletag :external

  describe "get_events/1" do
    test "fetches active events from Polymarket" do
      assert {:ok, events} = API.get_events(limit: 3)
      assert is_list(events)
      assert length(events) <= 3

      # Each event should have required fields
      Enum.each(events, fn event ->
        assert Map.has_key?(event, "id")
        assert Map.has_key?(event, "title")
        assert Map.has_key?(event, "markets")
      end)
    end

    test "respects limit parameter" do
      assert {:ok, events} = API.get_events(limit: 1)
      assert length(events) == 1
    end
  end

  describe "get_markets/1" do
    test "fetches active markets from Polymarket" do
      assert {:ok, markets} = API.get_markets(limit: 3)
      assert is_list(markets)
      assert length(markets) <= 3

      # Each market should have required fields
      Enum.each(markets, fn market ->
        assert Map.has_key?(market, "id")
        assert Map.has_key?(market, "question")
        assert Map.has_key?(market, "outcomePrices")
      end)
    end
  end

  describe "get_order_book/1" do
    test "fetches order book for valid token" do
      # First get a market to get a valid token ID
      {:ok, markets} = API.get_markets(limit: 1)
      [market | _] = markets

      case API.parse_token_ids(market) do
        {:ok, {yes_token, _no_token}} ->
          assert {:ok, book} = API.get_order_book(yes_token)
          assert Map.has_key?(book, "bids")
          assert Map.has_key?(book, "asks")

        _ ->
          # Skip if no token IDs available
          :ok
      end
    end
  end

  describe "parse_prices/1" do
    test "parses valid price strings" do
      market = %{"outcomePrices" => "[\"0.65\", \"0.35\"]"}
      assert {:ok, {0.65, 0.35}} = API.parse_prices(market)
    end

    test "handles invalid JSON" do
      market = %{"outcomePrices" => "invalid"}
      assert {:error, _} = API.parse_prices(market)
    end

    test "handles missing field" do
      market = %{}
      assert {:error, _} = API.parse_prices(market)
    end
  end

  describe "parse_token_ids/1" do
    test "parses valid token ID strings" do
      market = %{"clobTokenIds" => "[\"token1\", \"token2\"]"}
      assert {:ok, {"token1", "token2"}} = API.parse_token_ids(market)
    end

    test "handles invalid JSON" do
      market = %{"clobTokenIds" => "invalid"}
      assert {:error, _} = API.parse_token_ids(market)
    end
  end

  describe "check_arbitrage/2" do
    test "identifies arbitrage opportunity when total < 1.0" do
      assert {:opportunity, details} = API.check_arbitrage(0.45, 0.45)
      assert_in_delta details.total, 0.9, 0.0001
      assert_in_delta details.profit_per_pair, 0.1, 0.0001
      assert_in_delta details.profit_percentage, 10.0, 0.001
    end

    test "returns no opportunity when total >= 1.0" do
      assert {:no_opportunity, details} = API.check_arbitrage(0.50, 0.50)
      assert details.total == 1.0
    end

    test "returns no opportunity when total > 1.0" do
      assert {:no_opportunity, details} = API.check_arbitrage(0.55, 0.55)
      assert details.total == 1.1
    end
  end
end
