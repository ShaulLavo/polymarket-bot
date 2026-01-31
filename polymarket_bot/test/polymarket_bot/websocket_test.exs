defmodule PolymarketBot.WebSocketTest do
  @moduledoc """
  Tests for WebSocket message parsing logic.

  These tests verify the parsing functions without requiring
  a live WebSocket connection or the full application.
  """
  use ExUnit.Case, async: true

  # Test message parsing logic by directly testing the patterns

  describe "price data extraction from market/price format" do
    test "extracts all fields correctly" do
      data = %{
        "market" => "market123",
        "price" => 0.65,
        "token_id" => "token456"
      }

      result = extract_price_data(data)

      assert {:ok, price_data} = result
      assert price_data["market_id"] == "market123"
      assert price_data["token_id"] == "token456"
      assert price_data["yes_price"] == 0.65
      assert price_data["no_price"] == 0.35
      assert price_data["type"] == "price_update"
    end

    test "uses asset_id as fallback for token_id" do
      data = %{
        "market" => "market123",
        "price" => 0.5,
        "asset_id" => "asset789"
      }

      {:ok, result} = extract_price_data(data)
      assert result["token_id"] == "asset789"
    end
  end

  describe "price data extraction from asset_id/price format" do
    test "extracts all fields correctly" do
      data = %{
        "asset_id" => "asset789",
        "price" => "0.42"
      }

      {:ok, result} = extract_price_data(data)

      assert result["token_id"] == "asset789"
      assert result["market_id"] == "asset789"
      assert result["yes_price"] == 0.42
      assert_in_delta result["no_price"], 0.58, 0.0001
    end

    test "uses market_id if provided" do
      data = %{
        "asset_id" => "asset789",
        "price" => 0.5,
        "market_id" => "custom_market"
      }

      {:ok, result} = extract_price_data(data)
      assert result["market_id"] == "custom_market"
    end
  end

  describe "unknown message format handling" do
    test "returns :ignore for unknown format" do
      assert :ignore == extract_price_data(%{"unknown" => "data"})
    end

    test "returns :ignore for empty map" do
      assert :ignore == extract_price_data(%{})
    end

    test "returns :ignore when only price is present" do
      assert :ignore == extract_price_data(%{"price" => 0.5})
    end
  end

  describe "price parsing" do
    test "parses float price" do
      assert parse_price(0.65) == 0.65
    end

    test "parses integer price as float" do
      assert parse_price(1) == 1.0
      assert parse_price(0) == 0.0
    end

    test "parses string price" do
      assert parse_price("0.42") == 0.42
      assert parse_price("1.0") == 1.0
      assert parse_price("0") == 0.0
    end

    test "handles invalid string gracefully" do
      assert parse_price("invalid") == 0.0
      assert parse_price("") == 0.0
    end

    test "handles nil gracefully" do
      assert parse_price(nil) == 0.0
    end

    test "handles other types gracefully" do
      assert parse_price([]) == 0.0
      assert parse_price(%{}) == 0.0
    end
  end

  describe "timestamp parsing" do
    test "parses ISO8601 timestamp" do
      ts = "2026-01-31T12:00:00Z"
      result = parse_timestamp(ts)

      assert %DateTime{} = result
      assert result.year == 2026
      assert result.month == 1
      assert result.day == 31
      assert result.hour == 12
    end

    test "parses ISO8601 with timezone offset" do
      ts = "2026-01-31T12:00:00+00:00"
      result = parse_timestamp(ts)

      assert %DateTime{} = result
      assert result.year == 2026
    end

    test "parses unix millisecond timestamp" do
      # Jan 31, 2026 12:00:00 UTC in milliseconds
      ts = 1769860800000
      result = parse_timestamp(ts)

      assert %DateTime{} = result
    end

    test "returns utc_now for nil" do
      result = parse_timestamp(nil)
      assert %DateTime{} = result
      # Should be close to now
      diff = DateTime.diff(DateTime.utc_now(), result, :second)
      assert abs(diff) < 5
    end

    test "returns utc_now for invalid string format" do
      result = parse_timestamp("invalid")
      assert %DateTime{} = result
    end

    test "returns utc_now for unknown type" do
      result = parse_timestamp([])
      assert %DateTime{} = result
    end
  end

  describe "WebSocket state struct" do
    test "creates struct with nil defaults" do
      state = %PolymarketBot.WebSocket{}

      assert state.subscribed_markets == nil
      assert state.last_heartbeat == nil
      assert state.reconnect_attempts == nil
    end

    test "creates struct with provided values" do
      now = DateTime.utc_now()
      state = %PolymarketBot.WebSocket{
        subscribed_markets: ["market1", "market2"],
        last_heartbeat: now,
        reconnect_attempts: 0
      }

      assert length(state.subscribed_markets) == 2
      assert state.last_heartbeat == now
      assert state.reconnect_attempts == 0
    end

    test "struct fields can be updated" do
      state = %PolymarketBot.WebSocket{subscribed_markets: ["m1"]}
      updated = %{state | subscribed_markets: ["m1", "m2"]}

      assert length(updated.subscribed_markets) == 2
    end
  end

  # Helper functions that mirror the private functions in WebSocket module
  # This allows testing the parsing logic without starting a WebSocket connection

  defp extract_price_data(%{"market" => market_id, "price" => price} = data) do
    {:ok, %{
      "type" => "price_update",
      "market_id" => market_id,
      "token_id" => Map.get(data, "token_id") || Map.get(data, "asset_id"),
      "yes_price" => parse_price(price),
      "no_price" => 1.0 - parse_price(price),
      "timestamp" => Map.get(data, "timestamp") || DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp extract_price_data(%{"asset_id" => token_id, "price" => price} = data) do
    {:ok, %{
      "type" => "price_update",
      "market_id" => Map.get(data, "market_id", token_id),
      "token_id" => token_id,
      "yes_price" => parse_price(price),
      "no_price" => 1.0 - parse_price(price),
      "timestamp" => Map.get(data, "timestamp") || DateTime.utc_now() |> DateTime.to_iso8601()
    }}
  end

  defp extract_price_data(_), do: :ignore

  defp parse_price(price) when is_float(price), do: price
  defp parse_price(price) when is_integer(price), do: price / 1.0
  defp parse_price(price) when is_binary(price) do
    case Float.parse(price) do
      {val, _} -> val
      :error -> 0.0
    end
  end
  defp parse_price(_), do: 0.0

  defp parse_timestamp(nil), do: DateTime.utc_now()
  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_timestamp(ts) when is_integer(ts) do
    DateTime.from_unix!(ts, :millisecond)
  end
  defp parse_timestamp(_), do: DateTime.utc_now()
end
