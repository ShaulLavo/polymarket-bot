defmodule PolymarketBot.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias PolymarketBot.Router

  @opts Router.init([])

  describe "GET /health" do
    test "returns ok status" do
      conn = conn(:get, "/health")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body =~ "ok"

      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "ok"
      assert Map.has_key?(body, "timestamp")
    end
  end

  describe "GET /events" do
    @tag :external
    test "returns events from Polymarket" do
      conn = conn(:get, "/events?limit=2")
      conn = Router.call(conn, @opts)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "events")
      assert Map.has_key?(body, "count")
      assert is_list(body["events"])
    end
  end

  describe "GET /markets" do
    @tag :external
    test "returns markets from Polymarket" do
      conn = conn(:get, "/markets?limit=2")
      conn = Router.call(conn, @opts)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "markets")
      assert Map.has_key?(body, "count")
      assert is_list(body["markets"])

      # Check market structure
      if length(body["markets"]) > 0 do
        [market | _] = body["markets"]
        assert Map.has_key?(market, "id")
        assert Map.has_key?(market, "question")
        assert Map.has_key?(market, "yes_price")
        assert Map.has_key?(market, "no_price")
      end
    end
  end

  describe "GET /arbitrage" do
    @tag :external
    test "returns arbitrage scan results" do
      conn = conn(:get, "/arbitrage")
      conn = Router.call(conn, @opts)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "opportunities")
      assert Map.has_key?(body, "count")
      assert is_list(body["opportunities"])
    end
  end

  describe "GET /balance" do
    test "returns placeholder balance" do
      conn = conn(:get, "/balance")
      conn = Router.call(conn, @opts)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "balance")
    end
  end

  describe "404 handling" do
    test "returns 404 for unknown routes" do
      conn = conn(:get, "/unknown")
      conn = Router.call(conn, @opts)

      assert conn.status == 404

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "not found"
    end
  end
end
