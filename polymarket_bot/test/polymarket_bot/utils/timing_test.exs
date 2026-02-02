defmodule PolymarketBot.Utils.TimingTest do
  use ExUnit.Case, async: true

  alias PolymarketBot.Utils.Timing

  describe "get_window_timing/2" do
    test "returns correct window boundaries" do
      # 12:07:30 should be in window 12:00:00 - 12:15:00
      now = ~U[2024-01-15 12:07:30Z]
      timing = Timing.get_window_timing(15, now)

      assert timing.start_dt == ~U[2024-01-15 12:00:00Z]
      assert timing.end_dt == ~U[2024-01-15 12:15:00Z]
    end

    test "calculates elapsed and remaining time" do
      now = ~U[2024-01-15 12:10:00Z]
      timing = Timing.get_window_timing(15, now)

      # 10 minutes elapsed, 5 minutes remaining
      assert_in_delta timing.elapsed_minutes, 10.0, 0.01
      assert_in_delta timing.remaining_minutes, 5.0, 0.01
    end

    test "calculates progress correctly" do
      now = ~U[2024-01-15 12:07:30Z]
      timing = Timing.get_window_timing(15, now)

      # 7.5 minutes elapsed out of 15 = 50%
      assert_in_delta timing.progress, 0.5, 0.01
    end

    test "handles window at boundary" do
      now = ~U[2024-01-15 12:00:00Z]
      timing = Timing.get_window_timing(15, now)

      assert timing.start_dt == ~U[2024-01-15 12:00:00Z]
      assert_in_delta timing.elapsed_minutes, 0.0, 0.01
      assert_in_delta timing.remaining_minutes, 15.0, 0.01
    end

    test "works with different window sizes" do
      now = ~U[2024-01-15 12:05:00Z]
      timing = Timing.get_window_timing(5, now)

      assert timing.start_dt == ~U[2024-01-15 12:05:00Z]
      assert timing.end_dt == ~U[2024-01-15 12:10:00Z]
    end
  end

  describe "get_phase/1" do
    test "returns early for > 10 minutes" do
      assert Timing.get_phase(12.0) == :early
      assert Timing.get_phase(10.1) == :early
    end

    test "returns mid for 5-10 minutes" do
      assert Timing.get_phase(10.0) == :mid
      assert Timing.get_phase(7.5) == :mid
      assert Timing.get_phase(5.1) == :mid
    end

    test "returns late for <= 5 minutes" do
      assert Timing.get_phase(5.0) == :late
      assert Timing.get_phase(2.0) == :late
      assert Timing.get_phase(0.0) == :late
    end
  end

  describe "tradeable_window?/1" do
    test "returns false for first minute" do
      assert Timing.tradeable_window?(14.5) == false
    end

    test "returns false for last minute" do
      assert Timing.tradeable_window?(0.5) == false
    end

    test "returns true for middle of window" do
      assert Timing.tradeable_window?(7.0) == true
      assert Timing.tradeable_window?(10.0) == true
      assert Timing.tradeable_window?(2.0) == true
    end

    test "returns true at boundaries" do
      assert Timing.tradeable_window?(1.0) == true
      assert Timing.tradeable_window?(14.0) == true
    end
  end

  describe "next_window_start/2" do
    test "returns correct next window start" do
      now = ~U[2024-01-15 12:07:30Z]
      next = Timing.next_window_start(15, now)

      assert next == ~U[2024-01-15 12:15:00Z]
    end

    test "returns current end when at boundary" do
      now = ~U[2024-01-15 12:00:00Z]
      next = Timing.next_window_start(15, now)

      assert next == ~U[2024-01-15 12:15:00Z]
    end
  end

  describe "ms_until_next_window/2" do
    test "calculates milliseconds correctly" do
      now = ~U[2024-01-15 12:10:00Z]
      ms = Timing.ms_until_next_window(15, now)

      # 5 minutes = 300,000 ms
      assert ms == 300_000
    end
  end

  describe "format_remaining/1" do
    test "formats minutes and seconds" do
      assert Timing.format_remaining(7.5) == "7m 30s"
      assert Timing.format_remaining(0.5) == "0m 30s"
      assert Timing.format_remaining(10.0) == "10m 0s"
    end
  end

  describe "align_to_window/2" do
    test "aligns timestamp to window start" do
      ts = ~U[2024-01-15 12:07:30Z]
      aligned = Timing.align_to_window(ts, 15)

      assert aligned == ~U[2024-01-15 12:00:00Z]
    end

    test "preserves already aligned timestamps" do
      ts = ~U[2024-01-15 12:00:00Z]
      aligned = Timing.align_to_window(ts, 15)

      assert aligned == ~U[2024-01-15 12:00:00Z]
    end
  end
end
