defmodule PolymarketBot.Router do
  use Plug.Router
  alias PolymarketBot.API

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason
  )

  plug(:dispatch)

  # ============================================================================
  # HEALTH & STATUS
  # ============================================================================

  get "/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", timestamp: DateTime.utc_now()}))
  end

  # ============================================================================
  # MARKET DATA (Proxied from Polymarket)
  # ============================================================================

  # GET /events - Fetch active events from Polymarket
  # Query params: limit (default 10)
  get "/events" do
    limit = get_query_param(conn, "limit", "10") |> String.to_integer()

    case API.get_events(limit: limit) do
      {:ok, events} ->
        # Transform to simpler format
        simplified =
          Enum.map(events, fn event ->
            %{
              id: event["id"],
              title: event["title"],
              volume: event["volume"],
              liquidity: event["liquidity"],
              market_count: length(event["markets"] || [])
            }
          end)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{events: simplified, count: length(simplified)}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # GET /markets - Fetch active markets from Polymarket
  # Query params: limit (default 10)
  get "/markets" do
    limit = get_query_param(conn, "limit", "10") |> String.to_integer()

    case API.get_markets(limit: limit) do
      {:ok, markets} ->
        # Transform to simpler format with prices
        simplified =
          Enum.map(markets, fn market ->
            {yes_price, no_price} =
              case API.parse_prices(market) do
                {:ok, prices} -> prices
                _ -> {nil, nil}
              end

            %{
              id: market["id"],
              question: market["question"],
              slug: market["slug"],
              yes_price: yes_price,
              no_price: no_price,
              volume: market["volume"]
            }
          end)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{markets: simplified, count: length(simplified)}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # GET /book/:token_id - Fetch order book for a token
  get "/book/:token_id" do
    case API.get_order_book(token_id) do
      {:ok, book} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            token_id: token_id,
            bids: Enum.take(book["bids"] || [], 10),
            asks: Enum.take(book["asks"] || [], 10),
            timestamp: book["timestamp"]
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # GET /history/:token_id - Fetch price history
  # Query params: interval (1d, 1w, 1m, max), fidelity (seconds)
  get "/history/:token_id" do
    interval = get_query_param(conn, "interval", "1d")
    fidelity = get_query_param(conn, "fidelity", "60") |> String.to_integer()

    case API.get_price_history(token_id, interval: interval, fidelity: fidelity) do
      {:ok, data} ->
        history = data["history"] || []

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            token_id: token_id,
            interval: interval,
            fidelity: fidelity,
            data_points: length(history),
            history: history
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # GET /arbitrage - Scan markets for gabagool arbitrage opportunities
  get "/arbitrage" do
    case API.get_markets(limit: 50) do
      {:ok, markets} ->
        opportunities =
          markets
          |> Enum.map(fn market ->
            case API.parse_prices(market) do
              {:ok, {yes_price, no_price}} ->
                case API.check_arbitrage(yes_price, no_price) do
                  {:opportunity, details} ->
                    Map.merge(details, %{
                      question: market["question"],
                      slug: market["slug"]
                    })

                  _ ->
                    nil
                end

              _ ->
                nil
            end
          end)
          |> Enum.filter(& &1)
          |> Enum.sort_by(& &1.profit_percentage, :desc)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            opportunities: opportunities,
            count: length(opportunities)
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # ============================================================================
  # WALLET & BALANCE (placeholder)
  # ============================================================================

  get "/balance" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        balance: 0,
        note: "Connect wallet to see real balance"
      })
    )
  end

  # ============================================================================
  # CATCH-ALL
  # ============================================================================

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not found"}))
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp get_query_param(conn, key, default) do
    conn.query_params[key] || default
  end
end
