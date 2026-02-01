defmodule PolymarketBot.Backtester.PositionManager do
  @moduledoc """
  Manages multiple positions for the backtester.

  Supports:
  - Opening multiple concurrent positions
  - Scaling into/out of positions
  - Tracking unrealized P&L per position
  - Position-level and portfolio-level metrics

  ## State Structure

      %{
        cash: float(),
        positions: [position()],
        next_position_id: integer(),
        total_realized_pnl: float(),
        equity_curve: [float()]
      }

  ## Position Structure

      %{
        id: integer(),
        side: :long | :short,
        entry_price: float(),
        size: float(),
        entry_timestamp: DateTime.t(),
        entry_cost: float(),
        current_price: float(),
        unrealized_pnl: float(),
        metadata: map()
      }
  """

  alias PolymarketBot.Backtester.TradingCosts

  @doc """
  Initialize a new position manager state.
  """
  def init(initial_capital) do
    %{
      cash: initial_capital,
      positions: [],
      next_position_id: 1,
      total_realized_pnl: 0.0,
      equity_curve: [initial_capital]
    }
  end

  @doc """
  Open a new position.

  ## Parameters

  - `state` - Current position manager state
  - `side` - `:long` or `:short`
  - `price` - Entry price (mid-price, costs applied separately)
  - `size` - Position size in dollars
  - `timestamp` - Entry timestamp
  - `opts` - Options including:
    - `:costs_config` - Trading costs configuration
    - `:market_context` - Market context for cost calculation
    - `:metadata` - Additional metadata to store with position

  ## Returns

  `{:ok, new_state, position}` or `{:error, reason}`
  """
  def open_position(state, side, price, size, timestamp, opts \\ []) do
    costs_config = opts[:costs_config]
    market_context = opts[:market_context] || %{}
    metadata = opts[:metadata] || %{}

    # Apply trading costs if configured
    {execution_price, cost_breakdown} =
      if costs_config do
        {:ok, exec_price, costs} =
          TradingCosts.apply_costs(price, :buy, size, costs_config, market_context)

        {exec_price, costs}
      else
        {price, nil}
      end

    # Calculate the actual cash needed
    entry_cost = execution_price * size

    # Check if we have enough cash
    if entry_cost > state.cash do
      {:error, :insufficient_funds}
    else
      position = %{
        id: state.next_position_id,
        side: side,
        entry_price: execution_price,
        size: size,
        entry_timestamp: timestamp,
        entry_cost: entry_cost,
        current_price: execution_price,
        unrealized_pnl: 0.0,
        cost_breakdown: cost_breakdown,
        metadata: metadata
      }

      new_state = %{
        state
        | cash: state.cash - entry_cost,
          positions: [position | state.positions],
          next_position_id: state.next_position_id + 1
      }

      {:ok, new_state, position}
    end
  end

  @doc """
  Open a Gabagool arbitrage position (buying both YES and NO tokens).

  This is a specialized function for the Gabagool strategy that handles
  the dual-token nature of prediction market arbitrage.

  ## Parameters

  - `state` - Current position manager state
  - `yes_price` - YES token price
  - `no_price` - NO token price
  - `size` - Position size in dollars
  - `timestamp` - Entry timestamp
  - `opts` - Options including costs_config, market_context, metadata
  """
  def open_gabagool_position(state, yes_price, no_price, size, timestamp, opts \\ []) do
    costs_config = opts[:costs_config]
    market_context = opts[:market_context] || %{}
    metadata = opts[:metadata] || %{}

    # Calculate execution prices with costs
    {yes_exec_price, no_exec_price, cost_info} =
      if costs_config do
        cost_result =
          TradingCosts.estimate_gabagool_costs(
            yes_price,
            no_price,
            size,
            costs_config,
            market_context
          )

        {cost_result.yes_execution_price, cost_result.no_execution_price, cost_result}
      else
        {yes_price, no_price, nil}
      end

    # Total entry cost
    entry_cost = (yes_exec_price + no_exec_price) * size

    if entry_cost > state.cash do
      {:error, :insufficient_funds}
    else
      # Calculate the spread captured
      gross_spread = 1.0 - (yes_price + no_price)
      net_spread = 1.0 - (yes_exec_price + no_exec_price)

      position = %{
        id: state.next_position_id,
        side: :gabagool,
        yes_entry_price: yes_exec_price,
        no_entry_price: no_exec_price,
        entry_price: yes_exec_price + no_exec_price,
        size: size,
        entry_timestamp: timestamp,
        entry_cost: entry_cost,
        gross_spread: gross_spread,
        net_spread: net_spread,
        unrealized_pnl: net_spread * size,
        cost_info: cost_info,
        metadata: metadata
      }

      new_state = %{
        state
        | cash: state.cash - entry_cost,
          positions: [position | state.positions],
          next_position_id: state.next_position_id + 1
      }

      {:ok, new_state, position}
    end
  end

  @doc """
  Close a specific position by ID.

  ## Parameters

  - `state` - Current position manager state
  - `position_id` - ID of position to close
  - `price` - Exit price
  - `timestamp` - Exit timestamp
  - `opts` - Options including costs_config, market_context
  """
  def close_position(state, position_id, price, timestamp, opts \\ []) do
    case Enum.find(state.positions, &(&1.id == position_id)) do
      nil ->
        {:error, :position_not_found}

      position ->
        costs_config = opts[:costs_config]
        market_context = opts[:market_context] || %{}

        # Apply trading costs to exit
        execution_price =
          if costs_config do
            {:ok, exec_price, _costs} =
              TradingCosts.apply_costs(price, :sell, position.size, costs_config, market_context)

            exec_price
          else
            price
          end

        # Calculate realized P&L
        realized_pnl = calculate_position_pnl(position, execution_price)

        # Return cash + profit/loss
        returned_cash = position.entry_cost + realized_pnl

        closed_position =
          Map.merge(position, %{
            exit_price: execution_price,
            exit_timestamp: timestamp,
            realized_pnl: realized_pnl
          })

        new_state = %{
          state
          | cash: state.cash + returned_cash,
            positions: Enum.reject(state.positions, &(&1.id == position_id)),
            total_realized_pnl: state.total_realized_pnl + realized_pnl
        }

        {:ok, new_state, closed_position}
    end
  end

  @doc """
  Close all open positions.
  """
  def close_all_positions(state, price, timestamp, opts \\ []) do
    Enum.reduce(state.positions, {:ok, state, []}, fn position, {status, acc_state, closed} ->
      case status do
        :ok ->
          case close_position(acc_state, position.id, price, timestamp, opts) do
            {:ok, new_state, closed_pos} -> {:ok, new_state, [closed_pos | closed]}
            {:error, _} = err -> {err, acc_state, closed}
          end

        _ ->
          {status, acc_state, closed}
      end
    end)
  end

  @doc """
  Update unrealized P&L for all positions based on current prices.

  ## Parameters

  - `state` - Current state
  - `current_price` - Current market price (for standard positions)
  - `opts` - Options:
    - `:yes_price` - Current YES price (for gabagool positions)
    - `:no_price` - Current NO price (for gabagool positions)
  """
  def update_unrealized_pnl(state, current_price, opts \\ []) do
    yes_price = opts[:yes_price] || current_price
    _no_price = opts[:no_price] || 1.0 - yes_price

    updated_positions =
      Enum.map(state.positions, fn position ->
        unrealized_pnl =
          case position.side do
            :gabagool ->
              # For gabagool, profit is locked in at entry (spread captured)
              # The unrealized P&L is simply the net spread times size
              position.net_spread * position.size

            :long ->
              # Standard long position
              (current_price - position.entry_price) / position.entry_price *
                position.entry_cost

            :short ->
              # Standard short position
              (position.entry_price - current_price) / position.entry_price *
                position.entry_cost
          end

        %{position | current_price: current_price, unrealized_pnl: unrealized_pnl}
      end)

    # Calculate total equity
    total_unrealized = Enum.sum(Enum.map(updated_positions, & &1.unrealized_pnl))
    positions_cost = Enum.sum(Enum.map(updated_positions, & &1.entry_cost))
    total_equity = state.cash + positions_cost + total_unrealized

    # Update equity curve
    new_equity_curve = [total_equity | state.equity_curve]

    %{state | positions: updated_positions, equity_curve: new_equity_curve}
  end

  @doc """
  Get total portfolio equity (cash + positions value).
  """
  def get_total_equity(state) do
    positions_value =
      state.positions
      |> Enum.map(&(&1.entry_cost + &1.unrealized_pnl))
      |> Enum.sum()

    state.cash + positions_value
  end

  @doc """
  Get number of open positions.
  """
  def get_open_position_count(state) do
    length(state.positions)
  end

  @doc """
  Get positions by side.
  """
  def get_positions_by_side(state, side) do
    Enum.filter(state.positions, &(&1.side == side))
  end

  @doc """
  Scale into an existing position (add more size).
  """
  def scale_in(state, position_id, additional_size, price, _timestamp, opts \\ []) do
    case Enum.find(state.positions, &(&1.id == position_id)) do
      nil ->
        {:error, :position_not_found}

      position ->
        costs_config = opts[:costs_config]
        market_context = opts[:market_context] || %{}

        execution_price =
          if costs_config do
            {:ok, exec_price, _} =
              TradingCosts.apply_costs(price, :buy, additional_size, costs_config, market_context)

            exec_price
          else
            price
          end

        additional_cost = execution_price * additional_size

        if additional_cost > state.cash do
          {:error, :insufficient_funds}
        else
          # Calculate new average entry price
          total_cost = position.entry_cost + additional_cost
          total_size = position.size + additional_size
          new_avg_price = total_cost / total_size

          updated_position = %{
            position
            | entry_price: new_avg_price,
              size: total_size,
              entry_cost: total_cost
          }

          new_positions =
            Enum.map(state.positions, fn p ->
              if p.id == position_id, do: updated_position, else: p
            end)

          new_state = %{state | cash: state.cash - additional_cost, positions: new_positions}

          {:ok, new_state, updated_position}
        end
    end
  end

  @doc """
  Scale out of a position (reduce size).
  """
  def scale_out(state, position_id, reduce_size, price, timestamp, opts \\ []) do
    case Enum.find(state.positions, &(&1.id == position_id)) do
      nil ->
        {:error, :position_not_found}

      position ->
        if reduce_size >= position.size do
          # Close entire position
          close_position(state, position_id, price, timestamp, opts)
        else
          costs_config = opts[:costs_config]
          market_context = opts[:market_context] || %{}

          execution_price =
            if costs_config do
              {:ok, exec_price, _} =
                TradingCosts.apply_costs(price, :sell, reduce_size, costs_config, market_context)

              exec_price
            else
              price
            end

          # Calculate proportional cost being returned
          proportion = reduce_size / position.size
          cost_returned = position.entry_cost * proportion

          # Calculate P&L for the portion being closed
          partial_pnl = (execution_price - position.entry_price) * reduce_size

          returned_cash = cost_returned + partial_pnl

          updated_position = %{
            position
            | size: position.size - reduce_size,
              entry_cost: position.entry_cost - cost_returned
          }

          new_positions =
            Enum.map(state.positions, fn p ->
              if p.id == position_id, do: updated_position, else: p
            end)

          new_state = %{
            state
            | cash: state.cash + returned_cash,
              positions: new_positions,
              total_realized_pnl: state.total_realized_pnl + partial_pnl
          }

          {:ok, new_state, updated_position}
        end
    end
  end

  @doc """
  Get summary statistics for the position manager.
  """
  def get_summary(state) do
    total_equity = get_total_equity(state)

    total_unrealized =
      state.positions
      |> Enum.map(& &1.unrealized_pnl)
      |> Enum.sum()

    total_position_cost =
      state.positions
      |> Enum.map(& &1.entry_cost)
      |> Enum.sum()

    %{
      cash: state.cash,
      total_equity: total_equity,
      open_positions: length(state.positions),
      total_position_cost: total_position_cost,
      total_unrealized_pnl: total_unrealized,
      total_realized_pnl: state.total_realized_pnl,
      total_pnl: total_unrealized + state.total_realized_pnl
    }
  end

  # Private helpers

  defp calculate_position_pnl(position, exit_price) do
    case position.side do
      :gabagool ->
        # Gabagool positions resolve to $1.00, profit is the spread
        # Exit price is resolution price (should be 1.0)
        # But during backtest, we might exit early
        position.net_spread * position.size

      :long ->
        (exit_price - position.entry_price) / position.entry_price * position.entry_cost

      :short ->
        (position.entry_price - exit_price) / position.entry_price * position.entry_cost
    end
  end
end
