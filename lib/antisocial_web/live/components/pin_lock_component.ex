defmodule AntisocialWeb.PinLockComponent do
  use AntisocialWeb, :live_component

  alias Antisocial.Accounts

  def mount(socket) do
    {:ok, assign(socket, pin_input: "", error: nil, attempts: 0)}
  end

  def handle_event("submit_pin", %{"pin" => pin}, socket) do
    user = socket.assigns.current_user

    if Accounts.User.valid_pin?(user, pin) do
      send(self(), {:pin_unlocked, socket.assigns.context})
      {:noreply, assign(socket, pin_input: "", error: nil, attempts: 0)}
    else
      attempts = socket.assigns.attempts + 1
      {:noreply, assign(socket, pin_input: "", error: "wrong", attempts: attempts)}
    end
  end

  def handle_event("update_pin", %{"pin" => pin}, socket) do
    {:noreply, assign(socket, pin_input: pin)}
  end

  defp calculator_mode?(user) do
    user.tab_icon == "calculator"
  end

  def render(%{current_user: user} = assigns) do
    if calculator_mode?(user) do
      render_calculator(assigns)
    else
      render_pin_pad(assigns)
    end
  end

  # ── Standard PIN pad ──────────────────────────────────────────────────────

  defp render_pin_pad(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/95 backdrop-blur-sm">
      <div class="w-full max-w-xs p-8 bg-white dark:bg-gray-800 rounded-2xl shadow-xl text-center">
        <div class="mb-6">
          <div class="w-12 h-12 mx-auto mb-3 rounded-full bg-gray-100 dark:bg-gray-700 flex items-center justify-center">
            <.icon name="hero-lock-closed" class="w-6 h-6 text-gray-500 dark:text-gray-400" />
          </div>
        </div>
        <form phx-submit="submit_pin" phx-change="update_pin" phx-target={@myself}>
          <input
            type="password"
            name="pin"
            value={@pin_input}
            inputmode="numeric"
            maxlength="12"
            autofocus
            class="w-32 text-center text-2xl tracking-[0.5em] px-3 py-2 rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500 mb-4"
          />
          <button type="submit" class="w-full py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium transition-colors">
            Unlock
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Calculator PIN (disguised as a real calculator) ───────────────────────
  # JavaScript evaluates the expression; the result is sent as the PIN.
  # Someone without knowledge just sees a working calculator.

  defp render_calculator(assigns) do
    ~H"""
    <div
      id="calc-lock"
      class="fixed inset-0 z-50 bg-gray-900 flex flex-col select-none"
      phx-hook="CalculatorLock"
      phx-target={@myself}
    >
      <%!-- Display --%>
      <div class="flex-1 flex flex-col justify-end px-6 pb-4 min-h-0">
        <div id="calc-expr" class="text-gray-400 text-right text-lg truncate mb-1 min-h-[28px]"></div>
        <div id="calc-display" class="text-white text-right text-5xl font-light tracking-tight truncate">0</div>
      </div>

      <%!-- Hidden form — JS fills in the evaluated result before submit --%>
      <form id="calc-form" phx-submit="submit_pin" phx-target={@myself} class="hidden">
        <input type="hidden" name="pin" id="calc-pin-input" value="" />
      </form>

      <%!-- Button grid --%>
      <div class="grid grid-cols-4 gap-px bg-gray-700 border-t border-gray-700">
        <%!-- Row 1 --%>
        <%= for {label, cls, action} <- [
          {"AC",  "bg-gray-500 hover:bg-gray-400 text-white", "ac"},
          {"+/-", "bg-gray-500 hover:bg-gray-400 text-white", "sign"},
          {"%",   "bg-gray-500 hover:bg-gray-400 text-white", "pct"},
          {"÷",   "bg-orange-500 hover:bg-orange-400 text-white", "op:/"}
        ] do %>
          <button type="button" class={"calc-btn py-5 text-xl font-medium #{cls}"} data-action={action}><%= label %></button>
        <% end %>
        <%!-- Row 2 --%>
        <%= for {label, cls, action} <- [
          {"7", "bg-gray-800 hover:bg-gray-700 text-white", "digit:7"},
          {"8", "bg-gray-800 hover:bg-gray-700 text-white", "digit:8"},
          {"9", "bg-gray-800 hover:bg-gray-700 text-white", "digit:9"},
          {"×", "bg-orange-500 hover:bg-orange-400 text-white", "op:*"}
        ] do %>
          <button type="button" class={"calc-btn py-5 text-xl #{cls}"} data-action={action}><%= label %></button>
        <% end %>
        <%!-- Row 3 --%>
        <%= for {label, cls, action} <- [
          {"4", "bg-gray-800 hover:bg-gray-700 text-white", "digit:4"},
          {"5", "bg-gray-800 hover:bg-gray-700 text-white", "digit:5"},
          {"6", "bg-gray-800 hover:bg-gray-700 text-white", "digit:6"},
          {"−", "bg-orange-500 hover:bg-orange-400 text-white", "op:-"}
        ] do %>
          <button type="button" class={"calc-btn py-5 text-xl #{cls}"} data-action={action}><%= label %></button>
        <% end %>
        <%!-- Row 4 --%>
        <%= for {label, cls, action} <- [
          {"1", "bg-gray-800 hover:bg-gray-700 text-white", "digit:1"},
          {"2", "bg-gray-800 hover:bg-gray-700 text-white", "digit:2"},
          {"3", "bg-gray-800 hover:bg-gray-700 text-white", "digit:3"},
          {"+", "bg-orange-500 hover:bg-orange-400 text-white", "op:+"}
        ] do %>
          <button type="button" class={"calc-btn py-5 text-xl #{cls}"} data-action={action}><%= label %></button>
        <% end %>
        <%!-- Row 5 --%>
        <button type="button" class="calc-btn col-span-2 py-5 text-xl bg-gray-800 hover:bg-gray-700 text-white" data-action="digit:0">0</button>
        <button type="button" class="calc-btn py-5 text-xl bg-gray-800 hover:bg-gray-700 text-white" data-action="dot">.</button>
        <button type="button" class="calc-btn py-5 text-xl bg-orange-500 hover:bg-orange-400 text-white font-medium" data-action="equals">=</button>
      </div>
    </div>
    """
  end
end
