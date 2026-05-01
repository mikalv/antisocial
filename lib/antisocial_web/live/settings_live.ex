defmodule AntisocialWeb.SettingsLive do
  use AntisocialWeb, :live_view

  alias Antisocial.{Accounts, Repo}
  import Ecto.Query

  @icons [
    %{id: "bubbles_chat", label: "Chat-bobler"},
    %{id: "calculator", label: "Kalkulator"},
    %{id: "google", label: "Google"},
    %{id: "science", label: "Vitenskap"},
    %{id: "molecule_physics", label: "Fysikk"},
    %{id: "terminal", label: "Terminal"},
    %{id: "dns", label: "DNS"},
    %{id: "cms_admin", label: "Admin"},
    %{id: "development", label: "Utvikling"},
    %{id: "tech-chip", label: "Teknologi"},
    %{id: "cat_chat", label: "Katt"},
    %{id: "banana", label: "Banan"},
    %{id: "cannabis", label: "Urt"},
  ]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    other_users = Repo.all(from u in Accounts.User, where: u.id != ^user.id)

    aliases =
      Enum.map(other_users, fn u ->
        {u, Map.get(user.contact_aliases || %{}, to_string(u.id), "")}
      end)

    {:ok,
     assign(socket,
       icons: @icons,
       tab_icon: user.tab_icon || "bubbles_chat",
       tab_title: user.tab_title || "Notes",
       theme: user.theme || "system",
       idle_minutes: user.idle_minutes || 10,
       notification_mode: user.notification_mode || "stealth",
       contact_aliases: aliases,
       pin: "",
       pin_confirm: "",
       pin_error: nil,
       saved: false
     )}
  end

  def handle_event("select_icon", %{"icon" => icon}, socket) do
    {:noreply, assign(socket, tab_icon: icon, saved: false)}
  end

  def handle_event("update_title", %{"title" => title}, socket) do
    {:noreply, assign(socket, tab_title: title, saved: false)}
  end

  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, theme: theme, saved: false)}
  end

  def handle_event("set_idle", %{"minutes" => minutes}, socket) do
    {:noreply, assign(socket, idle_minutes: String.to_integer(minutes), saved: false)}
  end

  def handle_event("set_notification_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, notification_mode: mode, saved: false)}
  end

  def handle_event("update_alias", %{"user_id" => uid, "alias" => alias_name}, socket) do
    aliases =
      Enum.map(socket.assigns.contact_aliases, fn {u, current} ->
        if to_string(u.id) == uid, do: {u, alias_name}, else: {u, current}
      end)
    {:noreply, assign(socket, contact_aliases: aliases, saved: false)}
  end

  def handle_event("update_pin", %{"pin" => pin}, socket) do
    {:noreply, assign(socket, pin: pin, saved: false)}
  end

  def handle_event("update_pin_confirm", %{"pin" => pin}, socket) do
    {:noreply, assign(socket, pin_confirm: pin, saved: false)}
  end

  def handle_event("clear_pin", _params, socket) do
    Accounts.clear_pin(socket.assigns.current_user)
    {:noreply, assign(socket, pin: "", pin_confirm: "", pin_error: nil, saved: true)}
  end

  def handle_event("save", _params, socket) do
    user = socket.assigns.current_user
    s = socket.assigns

    with :ok <- validate_pin(s.pin, s.pin_confirm) do
      aliases_map =
        s.contact_aliases
        |> Enum.reject(fn {_, v} -> v == "" end)
        |> Enum.map(fn {u, v} -> {to_string(u.id), v} end)
        |> Map.new()

      Accounts.update_settings(user, %{
        theme: s.theme,
        tab_icon: s.tab_icon,
        tab_title: s.tab_title,
        idle_minutes: s.idle_minutes,
        notification_mode: s.notification_mode
      })

      user |> Accounts.User.contact_aliases_changeset(aliases_map) |> Repo.update()

      if s.pin != "" do
        Accounts.set_pin(user, s.pin)
      end

      {:noreply, assign(socket, saved: true, pin: "", pin_confirm: "", pin_error: nil)}
    else
      {:error, msg} -> {:noreply, assign(socket, pin_error: msg)}
    end
  end

  defp validate_pin("", _), do: :ok
  defp validate_pin(p, p) when byte_size(p) >= 4, do: :ok
  defp validate_pin(p, p), do: {:error, "PIN må være minst 4 tegn."}
  defp validate_pin(_, _), do: {:error, "PIN-kodene stemmer ikke."}

  def render(assigns) do
    ~H"""
    <div
      id="theme-root"
      phx-hook="ThemeHook"
      data-theme={@theme}
      class="min-h-screen bg-gray-50 dark:bg-gray-900"
    >
      <div class="max-w-2xl mx-auto p-6 space-y-10">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold text-gray-900 dark:text-white">Innstillinger</h1>
          <.link navigate={~p"/chat/generelt"} class="text-sm text-gray-400 hover:text-gray-600 dark:hover:text-gray-200">
            ← Tilbake
          </.link>
        </div>

        <%!-- Appearance --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Utseende</h2>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-5 border border-gray-100 dark:border-gray-700">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">Tema</label>
              <div class="flex gap-3">
                <%= for {value, label, icon} <- [{"light", "Lyst", "☀️"}, {"dark", "Mørkt", "🌙"}, {"system", "Auto", "⚙️"}] do %>
                  <button
                    phx-click="set_theme"
                    phx-value-theme={value}
                    class={"flex-1 py-3 rounded-xl border-2 text-sm transition-all text-center #{if @theme == value, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300", else: "border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:border-gray-300"}"}
                  >
                    <div class="text-lg mb-0.5"><%= icon %></div>
                    <%= label %>
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </section>

        <%!-- Tab disguise --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Fane-forkledning</h2>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-5 border border-gray-100 dark:border-gray-700">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">Ikon</label>
              <div class="grid grid-cols-5 gap-2 sm:grid-cols-7">
                <%= for icon <- @icons do %>
                  <button
                    phx-click="select_icon"
                    phx-value-icon={icon.id}
                    class={"p-2 rounded-xl border-2 transition-all flex flex-col items-center gap-1 #{if @tab_icon == icon.id, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30", else: "border-gray-100 dark:border-gray-700 hover:border-gray-300"}"}
                    title={icon.label}
                  >
                    <img src={"/icons/#{icon.id}.svg"} class="w-7 h-7" alt={icon.label} />
                    <span class="text-xs text-gray-500 dark:text-gray-400 truncate w-full text-center"><%= icon.label %></span>
                  </button>
                <% end %>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Fanetittel</label>
              <input
                type="text"
                name="title"
                value={@tab_title}
                phx-change="update_title"
                class="w-full px-3 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <p class="text-xs text-gray-400 mt-1">Vises i nettleserfanen og ved lagring på hjemskjerm.</p>
            </div>
          </div>
        </section>

        <%!-- Contact aliases --%>
        <%= if @contact_aliases != [] do %>
          <section class="space-y-4">
            <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Kontaktnavn</h2>
            <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 border border-gray-100 dark:border-gray-700">
              <p class="text-xs text-gray-400 dark:text-gray-500 mb-4">
                Endre hva kontaktene dine heter i chatten — kun synlig for deg.
              </p>
              <div class="space-y-3">
                <%= for {user, alias_val} <- @contact_aliases do %>
                  <div class="flex items-center gap-3">
                    <div class="w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900 flex items-center justify-center text-sm font-semibold text-blue-700 dark:text-blue-300 flex-shrink-0">
                      <%= String.first(user.username) |> String.upcase() %>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="text-xs text-gray-400 dark:text-gray-500 mb-0.5">Opprinnelig: <span class="font-mono"><%= user.username %></span></p>
                      <input
                        type="text"
                        placeholder={"Vis som... (f.eks. Tore)"}
                        value={alias_val}
                        phx-change="update_alias"
                        phx-value-user_id={user.id}
                        name={"alias[#{user.id}]"}
                        class="w-full px-3 py-1.5 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                      />
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </section>
        <% end %>

        <%!-- Notifications + lock --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Varsler og lås</h2>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-5 border border-gray-100 dark:border-gray-700">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Varsler</label>
              <div class="flex gap-3">
                <%= for {value, label} <- [{"active", "Aktiv"}, {"stealth", "Stille"}] do %>
                  <button
                    phx-click="set_notification_mode"
                    phx-value-mode={value}
                    class={"flex-1 py-2 rounded-xl border-2 text-sm transition-all #{if @notification_mode == value, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300", else: "border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:border-gray-300"}"}
                  >
                    <%= label %>
                  </button>
                <% end %>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Lås etter inaktivitet</label>
              <div class="grid grid-cols-4 gap-2">
                <%= for {mins, label} <- [{2, "2 min"}, {5, "5 min"}, {10, "10 min"}, {30, "30 min"}] do %>
                  <button
                    phx-click="set_idle"
                    phx-value-minutes={mins}
                    class={"py-2 rounded-lg border-2 text-sm transition-all #{if @idle_minutes == mins, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300", else: "border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:border-gray-300"}"}
                  >
                    <%= label %>
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </section>

        <%!-- PIN --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">PIN-kode</h2>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-3 border border-gray-100 dark:border-gray-700">
            <%= if @current_user.pin_hash do %>
              <p class="text-sm text-gray-500 dark:text-gray-400">PIN er satt. Skriv ny PIN for å endre, eller fjern den.</p>
              <button phx-click="clear_pin" class="text-sm text-red-500 hover:text-red-600">Fjern PIN</button>
            <% else %>
              <p class="text-sm text-gray-500 dark:text-gray-400">Ingen PIN satt. Legg til for ekstra beskyttelse.</p>
            <% end %>
            <input
              type="password"
              name="pin"
              inputmode="numeric"
              placeholder="Ny PIN (minst 4 tegn)"
              value={@pin}
              phx-change="update_pin"
              class="w-full px-3 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <%= if @pin != "" do %>
              <input
                type="password"
                name="pin_confirm"
                inputmode="numeric"
                placeholder="Gjenta PIN"
                value={@pin_confirm}
                phx-change="update_pin_confirm"
                class="w-full px-3 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            <% end %>
            <%= if @pin_error do %>
              <p class="text-xs text-red-500"><%= @pin_error %></p>
            <% end %>
          </div>
        </section>

        <%!-- Save --%>
        <div class="flex items-center gap-4 pb-8">
          <button
            phx-click="save"
            class="px-6 py-2.5 bg-blue-600 hover:bg-blue-700 text-white rounded-xl font-medium text-sm transition-colors"
          >
            Lagre innstillinger
          </button>
          <%= if @saved do %>
            <span class="text-sm text-green-500">✓ Lagret</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
