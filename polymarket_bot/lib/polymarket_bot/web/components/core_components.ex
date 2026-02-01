defmodule PolymarketBot.Web.CoreComponents do
  @moduledoc """
  Terminal-style UI components for the Polymarket Bot dashboard.

  Provides core building blocks with a retro terminal/hacker aesthetic.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash messages in terminal style.
  """
  attr(:flash, :map, required: true)
  attr(:kind, :atom, values: [:info, :error], doc: "flash message type")

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("#flash-#{@kind}")}
      role="alert"
      class={[
        "fixed top-4 right-4 z-50 p-4 border font-mono text-sm cursor-pointer",
        @kind == :info && "bg-green-900/50 border-green-500 text-green-400",
        @kind == :error && "bg-red-900/50 border-red-500 text-red-400"
      ]}
    >
      <div class="flex items-center gap-2">
        <span :if={@kind == :info}>[INFO]</span>
        <span :if={@kind == :error}>[ERROR]</span>
        <%= msg %>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with all flash messages.
  """
  attr(:flash, :map, required: true)

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    """
  end

  @doc """
  Terminal-style panel/box component.
  """
  attr(:title, :string, default: nil)
  attr(:class, :string, default: "")
  slot(:inner_block, required: true)

  def panel(assigns) do
    ~H"""
    <div class={["border border-green-500/30 bg-black/50", @class]}>
      <div :if={@title} class="border-b border-green-500/30 px-4 py-2 bg-green-900/20">
        <span class="text-amber-400 text-sm font-bold"><%= @title %></span>
      </div>
      <div class="p-4">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  @doc """
  Terminal-style button.
  """
  attr(:type, :string, default: "button")
  attr(:class, :string, default: "")
  attr(:rest, :global, include: ~w(disabled form name value))
  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "px-4 py-2 border border-green-500 bg-green-900/20 text-green-400",
        "hover:bg-green-500 hover:text-black transition-colors",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        "font-mono text-sm",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Terminal-style input field.
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)
  attr(:type, :string, default: "text")
  attr(:class, :string, default: "")

  attr(:rest, :global,
    include:
      ~w(autocomplete disabled form max maxlength min minlength pattern placeholder readonly required size step)
  )

  def input(assigns) do
    ~H"""
    <div class="space-y-1">
      <label :if={@label} for={@id} class="block text-sm text-green-500/70">
        <%= @label %>
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={@value}
        class={[
          "w-full px-3 py-2 bg-black border border-green-500/50 text-green-400",
          "focus:border-green-400 focus:outline-none focus:ring-1 focus:ring-green-400/50",
          "placeholder:text-green-500/30 font-mono text-sm",
          @class
        ]}
        {@rest}
      />
    </div>
    """
  end

  @doc """
  Terminal-style select dropdown.
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:options, :list, required: true)
  attr(:value, :any)
  attr(:class, :string, default: "")
  attr(:rest, :global, include: ~w(disabled form required))

  def select(assigns) do
    ~H"""
    <div class="space-y-1">
      <label :if={@label} for={@id} class="block text-sm text-green-500/70">
        <%= @label %>
      </label>
      <select
        name={@name}
        id={@id}
        class={[
          "w-full px-3 py-2 bg-black border border-green-500/50 text-green-400",
          "focus:border-green-400 focus:outline-none focus:ring-1 focus:ring-green-400/50",
          "font-mono text-sm",
          @class
        ]}
        {@rest}
      >
        <option :for={{label, value} <- @options} value={value} selected={@value == value}>
          <%= label %>
        </option>
      </select>
    </div>
    """
  end

  @doc """
  Stat display box with label and value.
  """
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:trend, :atom, default: nil, values: [nil, :up, :down])
  attr(:class, :string, default: "")

  def stat(assigns) do
    ~H"""
    <div class={["text-center p-3 border border-green-500/20 bg-green-900/10", @class]}>
      <div class="text-xs text-green-500/50 uppercase tracking-wider"><%= @label %></div>
      <div class={[
        "text-xl font-bold mt-1",
        @trend == :up && "text-green-400",
        @trend == :down && "text-red-400",
        is_nil(@trend) && "text-amber-400"
      ]}>
        <%= if @trend == :up, do: "+" %><%= @value %><%= if @trend == :down, do: "" %>
        <span :if={@trend == :up} class="text-xs">^</span>
        <span :if={@trend == :down} class="text-xs">v</span>
      </div>
    </div>
    """
  end

  @doc """
  Blinking cursor for terminal effect.
  """
  def cursor(assigns) do
    ~H"""
    <span class="animate-pulse">_</span>
    """
  end

  @doc """
  Progress bar in terminal style.
  """
  attr(:value, :integer, required: true)
  attr(:max, :integer, default: 100)
  attr(:class, :string, default: "")

  def progress(assigns) do
    pct = min(100, max(0, round(assigns.value / assigns.max * 100)))
    filled = round(pct / 5)
    empty = 20 - filled

    assigns = assign(assigns, pct: pct, filled: filled, empty: empty)

    ~H"""
    <div class={["font-mono text-sm", @class]}>
      <span class="text-green-500/50">[</span>
      <span class="text-green-400"><%= String.duplicate("=", @filled) %></span>
      <span class="text-green-500/30"><%= String.duplicate("-", @empty) %></span>
      <span class="text-green-500/50">]</span>
      <span class="text-amber-400 ml-2"><%= @pct %>%</span>
    </div>
    """
  end

  defp hide(js, selector) do
    JS.hide(js,
      to: selector,
      transition: {"transition-opacity duration-200", "opacity-100", "opacity-0"}
    )
  end
end
