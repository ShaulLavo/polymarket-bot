defmodule PolymarketBotTest do
  use ExUnit.Case

  test "application modules are defined" do
    assert Code.ensure_loaded?(PolymarketBot)
    assert Code.ensure_loaded?(PolymarketBot.API)
    assert Code.ensure_loaded?(PolymarketBot.Router)
    assert Code.ensure_loaded?(PolymarketBot.Repo)
    assert Code.ensure_loaded?(PolymarketBot.DataCollector)
  end

  test "schemas are defined" do
    assert Code.ensure_loaded?(PolymarketBot.Schema.Market)
    assert Code.ensure_loaded?(PolymarketBot.Schema.PriceSnapshot)
    assert Code.ensure_loaded?(PolymarketBot.Schema.OrderbookSnapshot)
  end
end
