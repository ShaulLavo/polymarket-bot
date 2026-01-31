defmodule PolymarketBot.API do
  @moduledoc """
  Client for Polymarket APIs (Gamma + CLOB).
  
  No authentication required for reading data.
  Trading requires EIP-712 signatures (see signet library).
  """

  @gamma_url "https://gamma-api.polymarket.com"
  @clob_url "https://clob.polymarket.com"

  # ============================================================================
  # GAMMA API - Market Discovery & Metadata
  # ============================================================================

  @doc """
  Fetch active events with their nested markets.
  
  ## Options
    * `:limit` - Number of events (default: 10)
    * `:active` - Only active events (default: true)
    * `:closed` - Include closed events (default: false)
  
  ## Example
      {:ok, events} = PolymarketBot.API.get_events(limit: 5)
  """
  def get_events(opts \\ []) do
    params = %{
      limit: Keyword.get(opts, :limit, 10),
      active: Keyword.get(opts, :active, true),
      closed: Keyword.get(opts, :closed, false)
    }

    case Req.get("#{@gamma_url}/events", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch markets directly (not nested under events).
  
  ## Options
    * `:limit` - Number of markets (default: 10)
    * `:active` - Only active markets (default: true)
    * `:closed` - Include closed markets (default: false)
    * `:enable_order_book` - Only markets with order books (default: true)
  """
  def get_markets(opts \\ []) do
    params = %{
      limit: Keyword.get(opts, :limit, 10),
      active: Keyword.get(opts, :active, true),
      closed: Keyword.get(opts, :closed, false),
      enableOrderBook: Keyword.get(opts, :enable_order_book, true)
    }

    case Req.get("#{@gamma_url}/markets", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch a single event by ID.
  """
  def get_event(event_id) do
    case Req.get("#{@gamma_url}/events/#{event_id}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # CLOB API - Order Books & Prices
  # ============================================================================

  @doc """
  Fetch the order book for a token.
  
  ## Example
      {:ok, book} = PolymarketBot.API.get_order_book("TOKEN_ID")
      # book.bids and book.asks contain the orders
  """
  def get_order_book(token_id) do
    case Req.get("#{@clob_url}/book", params: %{token_id: token_id}) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get current price for a token.
  """
  def get_price(token_id) do
    case Req.get("#{@clob_url}/price", params: %{token_id: token_id}) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get midpoint price for a token.
  """
  def get_midpoint(token_id) do
    case Req.get("#{@clob_url}/midpoint", params: %{token_id: token_id}) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get bid-ask spread for a token.
  """
  def get_spread(token_id) do
    case Req.get("#{@clob_url}/spread", params: %{token_id: token_id}) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch historical price data.
  
  ## Options
    * `:interval` - Time range: "1d", "1w", "1m", "max" (default: "1d")
    * `:fidelity` - Data point frequency in seconds (default: 60)
  
  ## Example
      {:ok, history} = PolymarketBot.API.get_price_history("TOKEN_ID", interval: "1w")
  """
  def get_price_history(token_id, opts \\ []) do
    params = %{
      market: token_id,
      interval: Keyword.get(opts, :interval, "1d"),
      fidelity: Keyword.get(opts, :fidelity, 60)
    }

    case Req.get("#{@clob_url}/prices-history", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  @doc """
  Parse token IDs from a market's clobTokenIds field.
  
  Returns {yes_token, no_token} tuple.
  """
  def parse_token_ids(market) when is_map(market) do
    token_ids_json = Map.get(market, "clobTokenIds", "[]")
    
    case Jason.decode(token_ids_json) do
      {:ok, [yes_token, no_token]} -> {:ok, {yes_token, no_token}}
      {:ok, _} -> {:error, :invalid_token_format}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parse outcome prices from a market.
  
  Returns {yes_price, no_price} as floats.
  """
  def parse_prices(market) when is_map(market) do
    prices_json = Map.get(market, "outcomePrices", "[]")
    
    case Jason.decode(prices_json) do
      {:ok, [yes_price, no_price]} -> 
        {:ok, {String.to_float(yes_price), String.to_float(no_price)}}
      {:ok, _} -> 
        {:error, :invalid_price_format}
      {:error, reason} -> 
        {:error, reason}
    end
  end

  @doc """
  Calculate potential arbitrage opportunity (Gabagool strategy).
  
  If yes_price + no_price < 1.0, there's an arb opportunity.
  """
  def check_arbitrage(yes_price, no_price) when is_float(yes_price) and is_float(no_price) do
    total = yes_price + no_price
    
    if total < 1.0 do
      profit_per_pair = 1.0 - total
      {:opportunity, %{
        yes_price: yes_price,
        no_price: no_price,
        total: total,
        profit_per_pair: profit_per_pair,
        profit_percentage: profit_per_pair * 100
      }}
    else
      {:no_opportunity, %{
        yes_price: yes_price,
        no_price: no_price,
        total: total
      }}
    end
  end
end
