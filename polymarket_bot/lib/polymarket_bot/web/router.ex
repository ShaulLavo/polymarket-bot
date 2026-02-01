defmodule PolymarketBot.Web.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PolymarketBot.Web.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", PolymarketBot.Web do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
    live("/backtest", BacktestLive, :index)
    live("/positions", PositionsLive, :index)
  end

  # API routes - delegate to existing router
  scope "/api" do
    pipe_through(:api)
    forward("/", PolymarketBot.Router)
  end
end
