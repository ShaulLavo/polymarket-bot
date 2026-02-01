defmodule PolymarketBot.Engines.Edge do
  @moduledoc """
  Edge computation engine for trade decision making.

  Computes the edge (model probability - market probability) and
  makes trading decisions based on phase-specific thresholds.
  """

  @type decision :: %{
          action: :enter | :no_trade,
          side: :up | :down | nil,
          phase: :early | :mid | :late,
          reason: String.t() | nil,
          strength: :strong | :good | :optional | nil,
          edge: float() | nil
        }

  @doc """
  Computes the edge between model and market probabilities.

  Edge = Model Probability - Market Probability

  ## Parameters

  Map with:
  - `:model_up` - Model's probability of up
  - `:model_down` - Model's probability of down
  - `:market_yes` - Market's yes price (raw)
  - `:market_no` - Market's no price (raw)

  ## Returns

  Map with:
  - `:market_up` - Normalized market up probability
  - `:market_down` - Normalized market down probability
  - `:edge_up` - Edge for up side
  - `:edge_down` - Edge for down side

  """
  @spec compute_edge(map()) :: %{
          market_up: float() | nil,
          market_down: float() | nil,
          edge_up: float() | nil,
          edge_down: float() | nil
        }
  def compute_edge(%{model_up: model_up, model_down: model_down} = params) do
    market_yes = Map.get(params, :market_yes)
    market_no = Map.get(params, :market_no)

    if is_nil(market_yes) or is_nil(market_no) do
      %{market_up: nil, market_down: nil, edge_up: nil, edge_down: nil}
    else
      sum = market_yes + market_no

      if sum > 0 do
        market_up = clamp(market_yes / sum, 0.0, 1.0)
        market_down = clamp(market_no / sum, 0.0, 1.0)

        edge_up = model_up - market_up
        edge_down = model_down - market_down

        %{
          market_up: market_up,
          market_down: market_down,
          edge_up: edge_up,
          edge_down: edge_down
        }
      else
        %{market_up: nil, market_down: nil, edge_up: nil, edge_down: nil}
      end
    end
  end

  def compute_edge(_) do
    %{market_up: nil, market_down: nil, edge_up: nil, edge_down: nil}
  end

  @doc """
  Makes a trading decision based on edge and time-based thresholds.

  ## Phase Thresholds

  | Phase | Time Remaining | Edge Threshold | Min Probability |
  |-------|----------------|----------------|-----------------|
  | EARLY | > 10 min       | 5%             | 55%             |
  | MID   | 5-10 min       | 10%            | 60%             |
  | LATE  | < 5 min        | 20%            | 65%             |

  ## Parameters

  Map with:
  - `:remaining_minutes` - Minutes until window closes
  - `:edge_up` - Edge for up side
  - `:edge_down` - Edge for down side
  - `:model_up` - Model probability for up (optional)
  - `:model_down` - Model probability for down (optional)

  ## Returns

  Map with:
  - `:action` - :enter or :no_trade
  - `:side` - :up or :down (nil if no_trade)
  - `:phase` - :early, :mid, or :late
  - `:reason` - Explanation (for no_trade)
  - `:strength` - :strong, :good, or :optional (for enter)
  - `:edge` - The edge value (for enter)

  """
  @spec decide(map()) :: decision()
  def decide(params) when is_map(params) do
    remaining_minutes = Map.get(params, :remaining_minutes, 0)
    edge_up = Map.get(params, :edge_up)
    edge_down = Map.get(params, :edge_down)
    model_up = Map.get(params, :model_up)
    model_down = Map.get(params, :model_down)

    phase = determine_phase(remaining_minutes)
    {threshold, min_prob} = phase_thresholds(phase)

    cond do
      is_nil(edge_up) or is_nil(edge_down) ->
        %{
          action: :no_trade,
          side: nil,
          phase: phase,
          reason: "missing_market_data",
          strength: nil,
          edge: nil
        }

      true ->
        # Determine best side
        {best_side, best_edge, best_model} =
          if edge_up > edge_down do
            {:up, edge_up, model_up}
          else
            {:down, edge_down, model_down}
          end

        cond do
          best_edge < threshold ->
            %{
              action: :no_trade,
              side: nil,
              phase: phase,
              reason: "edge_below_#{threshold}",
              strength: nil,
              edge: nil
            }

          not is_nil(best_model) and best_model < min_prob ->
            %{
              action: :no_trade,
              side: nil,
              phase: phase,
              reason: "prob_below_#{min_prob}",
              strength: nil,
              edge: nil
            }

          true ->
            strength = determine_strength(best_edge)

            %{
              action: :enter,
              side: best_side,
              phase: phase,
              reason: nil,
              strength: strength,
              edge: best_edge
            }
        end
    end
  end

  def decide(_) do
    %{
      action: :no_trade,
      side: nil,
      phase: :early,
      reason: "invalid_params",
      strength: nil,
      edge: nil
    }
  end

  # Private helpers

  defp determine_phase(remaining_minutes) when is_number(remaining_minutes) do
    cond do
      remaining_minutes > 10 -> :early
      remaining_minutes > 5 -> :mid
      true -> :late
    end
  end

  defp determine_phase(_), do: :early

  defp phase_thresholds(:early), do: {0.05, 0.55}
  defp phase_thresholds(:mid), do: {0.10, 0.60}
  defp phase_thresholds(:late), do: {0.20, 0.65}

  defp determine_strength(edge) when is_number(edge) do
    cond do
      edge >= 0.20 -> :strong
      edge >= 0.10 -> :good
      true -> :optional
    end
  end

  defp determine_strength(_), do: :optional

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
