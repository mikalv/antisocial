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
      {:noreply, assign(socket, pin_input: "", error: "Feil PIN (#{attempts})", attempts: attempts)}
    end
  end

  def handle_event("update_pin", %{"pin" => pin}, socket) do
    {:noreply, assign(socket, pin_input: pin)}
  end

  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/95 backdrop-blur-sm">
      <div class="w-full max-w-xs p-8 bg-white dark:bg-gray-800 rounded-2xl shadow-xl text-center">
        <div class="mb-6">
          <div class="w-12 h-12 mx-auto mb-3 rounded-full bg-gray-100 dark:bg-gray-700 flex items-center justify-center">
            <.icon name="hero-lock-closed" class="w-6 h-6 text-gray-500 dark:text-gray-400" />
          </div>
          <p class="text-sm text-gray-500 dark:text-gray-400">Skriv inn PIN for å låse opp</p>
        </div>

        <form phx-submit="submit_pin" phx-change="update_pin" phx-target={@myself}>
          <div class="flex justify-center gap-3 mb-4">
            <input
              type="password"
              name="pin"
              value={@pin_input}
              inputmode="numeric"
              maxlength="12"
              autofocus
              class="w-32 text-center text-2xl tracking-[0.5em] px-3 py-2 rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <%= if @error do %>
            <p class="text-sm text-red-500 mb-3"><%= @error %></p>
          <% end %>
          <button
            type="submit"
            class="w-full py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium transition-colors"
          >
            Lås opp
          </button>
        </form>
      </div>
    </div>
    """
  end
end
