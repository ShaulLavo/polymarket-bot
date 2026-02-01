defmodule PolymarketBot.Web.Layouts do
  @moduledoc """
  Terminal-style layouts for the Polymarket Bot dashboard.
  """
  use PolymarketBot.Web, :html

  embed_templates("layouts/*")
end
