defmodule PolymarketBot.Backtester.Strategies.TASignals do
  @moduledoc """
  Technical Analysis Signals Strategy for Polymarket BTC prediction markets.

  This strategy combines multiple technical indicators to estimate the
  probability of BTC price moving up or down within a 15-minute window.

  ## Indicators Used

  - **VWAP**: Volume-Weighted Average Price for trend bias
  - **RSI**: Relative Strength Index for momentum
  - **MACD**: Moving Average Convergence/Divergence for trend strength
  - **Heiken Ashi**: Smoothed candles for trend confirmation

  ## Decision Logic

  1. Compute all indicators from BTC price candles
  2. Score direction (up/down) using weighted signals
  3. Apply time decay as window expiry approaches
  4. Compare model probability to market probability
  5. Enter trade if edge exceeds phase-specific threshold

  ## Configuration

  - `:candles` - Pre-fetched Binance candles (required for backtesting)
  - `:window_minutes` - Trading window duration (default: 15)
  - `:vwap_slope_lookback` - Periods for VWAP slope (default: 5)
  - `:rsi_period` - RSI calculation period (default: 14)
  - `:macd_fast` - MACD fast period (default: 12)
  - `:macd_slow` - MACD slow period (default: 26)
  - `:macd_signal` - MACD signal period (default: 9)
  """

  @behaviour PolymarketBot.Backtester.Strategy

  alias PolymarketBot.Indicators.{VWAP, RSI, MACD, HeikenAshi}
  alias PolymarketBot.Engines.{Probability, Edge, Regime}
  alias PolymarketBot.Utils.Timing

  @default_config %{
    window_minutes: 15,
    vwap_slope_lookback: 5,
    rsi_period: 14,
    rsi_slope_lookback: 3,
    macd_fast: 12,
    macd_slow: 26,
    macd_signal: 9,
    position_size: 1.0,
    min_candles: 30
  }

  @impl true
  def name, do: "TASignals"

  @impl true
  def default_config, do: @default_config

  @impl true
  def init(config) do
    config = Map.merge(@default_config, config || %{})

    state = %{
      config: config,
      candles: Map.get(config, :candles, []),
      current_window: nil,
      position: nil,
      entry_price: nil,
      entry_side: nil,
      trades: [],
      signals: []
    }

    {:ok, state}
  end

  @impl true
  def on_price(price_data, state) do
    %{yes_price: market_yes, no_price: market_no, timestamp: timestamp} = price_data
    %{config: config, candles: candles} = state

    # Determine current window timing
    timing = Timing.get_window_timing(config.window_minutes, timestamp)
    remaining_minutes = timing.remaining_minutes

    # Check if we have enough candle data
    if length(candles) < config.min_candles do
      {:hold, state}
    else
      # Compute all indicators
      indicators = compute_indicators(candles, config)

      # Score direction
      score_inputs = build_score_inputs(indicators, candles)
      direction_score = Probability.score_direction(score_inputs)

      # Apply time awareness
      time_adjusted =
        Probability.apply_time_awareness(
          direction_score.raw_up,
          remaining_minutes,
          config.window_minutes
        )

      model_up = time_adjusted.adjusted_up
      model_down = time_adjusted.adjusted_down

      # Compute edge vs market
      edge_result =
        Edge.compute_edge(%{
          model_up: model_up,
          model_down: model_down,
          market_yes: market_yes,
          market_no: market_no
        })

      # Make trading decision
      decision =
        Edge.decide(%{
          remaining_minutes: remaining_minutes,
          edge_up: edge_result.edge_up,
          edge_down: edge_result.edge_down,
          model_up: model_up,
          model_down: model_down
        })

      # Detect regime for context
      regime_result = detect_current_regime(candles, config)

      # Store signal for analysis
      signal = %{
        timestamp: timestamp,
        remaining_minutes: remaining_minutes,
        phase: decision.phase,
        indicators: indicators,
        direction_score: direction_score,
        model_up: model_up,
        model_down: model_down,
        market_yes: market_yes,
        market_no: market_no,
        edge_up: edge_result.edge_up,
        edge_down: edge_result.edge_down,
        decision: decision,
        regime: regime_result.regime
      }

      state = %{state | signals: [signal | state.signals]}

      # Execute trading logic
      execute_decision(decision, price_data, state)
    end
  end

  @impl true
  def on_complete(state) do
    stats = %{
      total_trades: length(state.trades),
      trades: Enum.reverse(state.trades),
      signals: Enum.reverse(state.signals) |> Enum.take(100),
      final_position: state.position,
      win_rate: calculate_win_rate(state.trades),
      avg_edge: calculate_avg_edge(state.trades)
    }

    {:ok, stats}
  end

  # Private functions

  defp compute_indicators(candles, config) do
    closes = Enum.map(candles, & &1.close)

    # VWAP
    vwap = VWAP.compute_session_vwap(candles)
    vwap_series = VWAP.compute_vwap_series(candles)
    vwap_slope = VWAP.compute_slope(vwap_series, config.vwap_slope_lookback)

    # RSI
    rsi = RSI.compute_rsi(closes, config.rsi_period)
    rsi_series = RSI.compute_rsi_series(closes, config.rsi_period)
    rsi_slope = RSI.slope_last(Enum.reject(rsi_series, &is_nil/1), config.rsi_slope_lookback)

    # MACD
    macd = MACD.compute_macd(closes, config.macd_fast, config.macd_slow, config.macd_signal)

    # Heiken Ashi
    ha_candles = HeikenAshi.compute_heiken_ashi(candles)
    ha_consecutive = HeikenAshi.count_consecutive(ha_candles)

    # Current price
    current_price = List.last(closes)

    # VWAP crosses
    vwap_cross_count =
      if length(closes) == length(vwap_series) do
        VWAP.count_crosses(closes, vwap_series)
      else
        0
      end

    %{
      price: current_price,
      vwap: vwap,
      vwap_slope: vwap_slope,
      vwap_cross_count: vwap_cross_count,
      rsi: rsi,
      rsi_slope: rsi_slope,
      macd: macd,
      heiken_color: ha_consecutive.color,
      heiken_count: ha_consecutive.count
    }
  end

  defp build_score_inputs(indicators, candles) do
    # Detect failed VWAP reclaim pattern
    failed_vwap_reclaim = detect_failed_vwap_reclaim(candles, indicators.vwap)

    Map.put(indicators, :failed_vwap_reclaim, failed_vwap_reclaim)
  end

  defp detect_failed_vwap_reclaim(candles, vwap) when length(candles) >= 5 and not is_nil(vwap) do
    recent = Enum.take(candles, -5)

    # Pattern: price was below VWAP, crossed above, then fell back below
    closes = Enum.map(recent, & &1.close)

    below_before =
      closes
      |> Enum.take(2)
      |> Enum.all?(fn c -> c < vwap end)

    crossed_above =
      closes
      |> Enum.drop(1)
      |> Enum.take(2)
      |> Enum.any?(fn c -> c > vwap end)

    back_below =
      closes
      |> Enum.take(-1)
      |> Enum.all?(fn c -> c < vwap end)

    below_before and crossed_above and back_below
  end

  defp detect_failed_vwap_reclaim(_, _), do: false

  defp detect_current_regime(candles, config) do
    closes = Enum.map(candles, & &1.close)
    volumes = Enum.map(candles, & &1.volume)

    vwap = VWAP.compute_session_vwap(candles)
    vwap_series = VWAP.compute_vwap_series(candles)
    vwap_slope = VWAP.compute_slope(vwap_series, config.vwap_slope_lookback)

    price = List.last(closes)

    vwap_cross_count =
      if length(closes) == length(vwap_series) do
        VWAP.count_crosses(closes, vwap_series)
      else
        0
      end

    # Volume analysis
    volume_recent = Enum.take(volumes, -5) |> Enum.sum() |> Kernel./(5)
    volume_avg = Enum.sum(volumes) / length(volumes)

    Regime.detect_regime(%{
      price: price,
      vwap: vwap,
      vwap_slope: vwap_slope,
      vwap_cross_count: vwap_cross_count,
      volume_recent: volume_recent,
      volume_avg: volume_avg
    })
  end

  defp execute_decision(decision, price_data, state) do
    %{config: config, position: position} = state
    %{yes_price: market_yes, no_price: market_no, timestamp: _timestamp} = price_data

    case {decision.action, position} do
      # Enter new position
      {:enter, nil} ->
        entry_price = if decision.side == :up, do: market_yes, else: market_no

        state = %{
          state
          | position: :long,
            entry_price: entry_price,
            entry_side: decision.side
        }

        {{:buy, config.position_size}, state}

      # Already in position, check for exit or hold
      {:enter, :long} ->
        # Could add logic to switch sides or add to position
        {:hold, state}

      # No trade signal
      {:no_trade, nil} ->
        {:hold, state}

      # Close position at window end (would need timestamp tracking)
      {:no_trade, :long} ->
        # For now, hold until explicit exit signal
        {:hold, state}

      _ ->
        {:hold, state}
    end
  end

  defp calculate_win_rate([]), do: 0.0

  defp calculate_win_rate(trades) do
    wins = Enum.count(trades, fn t -> t[:return] > 0 end)
    wins / length(trades) * 100
  end

  defp calculate_avg_edge([]), do: 0.0

  defp calculate_avg_edge(trades) do
    edges = Enum.map(trades, fn t -> t[:edge] || 0 end)
    Enum.sum(edges) / length(edges)
  end

  # Public helper for running analysis on historical data

  @doc """
  Analyzes historical candles and returns signal history.

  This is useful for backtesting and strategy evaluation.

  ## Parameters

  - `candles` - List of OHLCV candles from Binance
  - `config` - Strategy configuration (optional)

  ## Returns

  Map with `:signals` and `:summary` keys.
  """
  @spec analyze_historical([map()], map()) :: map()
  def analyze_historical(candles, config \\ %{}) do
    config = Map.merge(@default_config, config)

    # Group candles into windows
    windows = group_candles_by_window(candles, config.window_minutes)

    # Analyze each window
    signals =
      windows
      |> Enum.map(fn {window_start, window_candles} ->
        if length(window_candles) >= config.min_candles do
          indicators = compute_indicators(window_candles, config)
          score_inputs = build_score_inputs(indicators, window_candles)
          direction_score = Probability.score_direction(score_inputs)
          regime = detect_current_regime(window_candles, config)

          %{
            window_start: DateTime.from_unix!(window_start, :millisecond),
            indicators: indicators,
            direction_score: direction_score,
            regime: regime.regime,
            raw_up: direction_score.raw_up
          }
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Summary statistics
    summary = %{
      total_windows: length(signals),
      avg_raw_up: avg_field(signals, [:direction_score, :raw_up]),
      regime_distribution: count_regimes(signals)
    }

    %{signals: signals, summary: summary}
  end

  defp group_candles_by_window(candles, window_minutes) do
    window_ms = window_minutes * 60 * 1000

    candles
    |> Enum.group_by(fn c -> div(c.open_time, window_ms) * window_ms end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end

  defp avg_field([], _), do: 0.0

  defp avg_field(items, path) do
    values =
      items
      |> Enum.map(fn item -> get_in(item, path) end)
      |> Enum.reject(&is_nil/1)

    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0.0
    end
  end

  defp count_regimes(signals) do
    signals
    |> Enum.group_by(& &1.regime)
    |> Enum.map(fn {regime, items} -> {regime, length(items)} end)
    |> Map.new()
  end
end
