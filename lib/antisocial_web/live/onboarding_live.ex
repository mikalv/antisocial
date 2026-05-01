defmodule AntisocialWeb.OnboardingLive do
  use AntisocialWeb, :live_view

  alias Antisocial.Accounts

  @icons [
    %{id: "bubbles_chat", label: "Chat-bobler", hint: nil},
    %{id: "calculator", label: "Kalkulator", hint: "Skjult"},
    %{id: "google", label: "Google", hint: "Skjult"},
    %{id: "science", label: "Vitenskap", hint: "Skjult"},
    %{id: "molecule_physics", label: "Fysikk", hint: "Skjult"},
    %{id: "terminal", label: "Terminal", hint: "Skjult"},
    %{id: "dns", label: "DNS", hint: "Skjult"},
    %{id: "cms_admin", label: "Admin", hint: "Skjult"},
    %{id: "development", label: "Utvikling", hint: "Skjult"},
    %{id: "tech-chip", label: "Teknologi", hint: "Skjult"},
    %{id: "cat_chat", label: "Katt", hint: nil},
    %{id: "banana", label: "Banan", hint: nil},
    %{id: "cannabis", label: "Urt", hint: nil},
  ]

  @disguise_titles %{
    "calculator" => "Kalkulator",
    "google" => "Google",
    "science" => "Science Notes",
    "molecule_physics" => "Physics",
    "terminal" => "Terminal",
    "dns" => "Network Tools",
    "cms_admin" => "Admin Panel",
    "development" => "Dev Notes",
    "tech-chip" => "Tech Monitor",
    "bubbles_chat" => "Meldinger",
    "cat_chat" => "Meldinger",
    "banana" => "Meldinger",
    "cannabis" => "Urter",
  }

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     assign(socket,
       step: 0,
       disguise: nil,
       selected_icon: "bubbles_chat",
       tab_title: "Meldinger",
       theme: "system",
       idle_minutes: 10,
       pin: "",
       pin_confirm: "",
       pin_error: nil,
       icons: @icons
     )}
  end

  # ── Step navigation ────────────────────────────────────────────────────────

  def handle_event("choose_disguise", %{"value" => value}, socket) do
    disguise = value == "yes"
    icon = if disguise, do: "calculator", else: "bubbles_chat"
    title = @disguise_titles[icon]
    # yes → go to icon picker (step 2), no → skip to theme (step 3)
    {:noreply, assign(socket, disguise: disguise, selected_icon: icon, tab_title: title, step: if(disguise, do: 2, else: 3))}
  end

  def handle_event("select_icon", %{"icon" => icon}, socket) do
    title = @disguise_titles[icon] || socket.assigns.tab_title
    {:noreply, assign(socket, selected_icon: icon, tab_title: title)}
  end

  def handle_event("update_title", %{"title" => title}, socket) do
    {:noreply, assign(socket, tab_title: title)}
  end

  def handle_event("next_step", _params, socket) do
    {:noreply, assign(socket, step: socket.assigns.step + 1)}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, step: socket.assigns.step - 1)}
  end

  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, theme: theme)}
  end

  def handle_event("set_idle", %{"minutes" => minutes}, socket) do
    {:noreply, assign(socket, idle_minutes: String.to_integer(minutes))}
  end

  def handle_event("update_pin", %{"pin" => pin}, socket) do
    {:noreply, assign(socket, pin: pin)}
  end

  def handle_event("update_pin_confirm", %{"pin" => pin}, socket) do
    {:noreply, assign(socket, pin_confirm: pin)}
  end

  def handle_event("finish", _params, socket) do
    user = socket.assigns.current_user
    s = socket.assigns

    # Validate PIN if provided
    if s.pin != "" and s.pin != s.pin_confirm do
      {:noreply, assign(socket, pin_error: "PIN-kodene stemmer ikke.")}
    else
      # Save settings
      Accounts.update_settings(user, %{
        theme: s.theme,
        tab_icon: s.selected_icon,
        tab_title: s.tab_title,
        idle_minutes: s.idle_minutes
      })

      if s.pin != "" do
        Accounts.set_pin(user, s.pin)
      end

      Accounts.mark_onboarded(user)

      {:noreply, push_navigate(socket, to: "/chat/generelt")}
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div
      id="theme-root"
      phx-hook="ThemeHook"
      data-theme={@theme}
      class="min-h-screen bg-gray-50 dark:bg-gray-900 flex items-center justify-center p-4"
    >
      <div class="w-full max-w-lg bg-white dark:bg-gray-800 rounded-2xl shadow-sm p-8">
        <%!-- Progress dots (steps 1–4, hidden on step 0) --%>
        <%= if @step > 0 do %>
          <div class="flex justify-center gap-2 mb-8">
            <%= for i <- 1..4 do %>
              <div class={"w-2 h-2 rounded-full transition-colors #{if i == @step, do: "bg-blue-600", else: if(i < @step, do: "bg-blue-200 dark:bg-blue-800", else: "bg-gray-200 dark:bg-gray-700")}"} />
            <% end %>
          </div>
        <% end %>

        <%!-- Step 0: Personal welcome --%>
        <%= if @step == 0 do %>
          <div class="text-center space-y-8 py-4">
            <div class="space-y-3">
              <div class="text-4xl">👋</div>
              <h2 class="text-2xl font-semibold text-gray-900 dark:text-white">
                Denne appen er laget for deg<%= if name = @current_user.display_name, do: ", #{name}", else: "" %>.
              </h2>
              <p class="text-sm text-gray-400 dark:text-gray-500 max-w-xs mx-auto">
                Vi setter opp ting slik du vil ha det. Tar ett minutt.
              </p>
            </div>
            <button
              phx-click="next_step"
              class="px-8 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-xl font-medium transition-colors"
            >
              Kom i gang →
            </button>
          </div>
        <% end %>

        <%!-- Step 1: Disguise choice --%>
        <%= if @step == 1 do %>
          <div class="text-center space-y-6">
            <div>
              <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">Velkommen</h2>
              <p class="text-sm text-gray-500 dark:text-gray-400">
                Vil du at appen skal se ut som noe annet i nettleserfanen og på hjemskjermen?
              </p>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <button
                phx-click="choose_disguise"
                phx-value-value="yes"
                class="p-4 rounded-xl border-2 border-gray-200 dark:border-gray-600 hover:border-blue-400 dark:hover:border-blue-500 transition-colors text-center"
              >
                <div class="text-2xl mb-1">🎭</div>
                <div class="text-sm font-medium text-gray-700 dark:text-gray-300">Ja, skjul den</div>
                <div class="text-xs text-gray-400 mt-0.5">Velg et annet ikon og navn</div>
              </button>
              <button
                phx-click="choose_disguise"
                phx-value-value="no"
                class="p-4 rounded-xl border-2 border-gray-200 dark:border-gray-600 hover:border-blue-400 dark:hover:border-blue-500 transition-colors text-center"
              >
                <div class="text-2xl mb-1">💬</div>
                <div class="text-sm font-medium text-gray-700 dark:text-gray-300">Nei, vanlig</div>
                <div class="text-xs text-gray-400 mt-0.5">Bruk standard ikon</div>
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Step 2: Icon + title picker (only if disguise chosen) --%>
        <%= if @step == 2 do %>
          <div class="space-y-6">
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-1">Velg forkledning</h2>
              <p class="text-xs text-gray-400 dark:text-gray-500">Ikonet og tittelen vises i nettleserfanen og ved lagring på hjemskjermen.</p>
            </div>

            <div class="grid grid-cols-4 gap-2">
              <%= for icon <- @icons do %>
                <button
                  phx-click="select_icon"
                  phx-value-icon={icon.id}
                  class={"p-2 rounded-xl border-2 transition-all flex flex-col items-center gap-1 #{if @selected_icon == icon.id, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30", else: "border-gray-100 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-500"}"}
                >
                  <img src={"/icons/#{icon.id}.svg"} class="w-8 h-8" alt={icon.label} />
                  <span class="text-xs text-gray-600 dark:text-gray-400 truncate w-full text-center"><%= icon.label %></span>
                  <%= if icon.hint do %>
                    <span class="text-xs text-amber-500">← bra</span>
                  <% end %>
                </button>
              <% end %>
            </div>

            <div>
              <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Fanens tittel</label>
              <input
                type="text"
                value={@tab_title}
                phx-change="update_title"
                name="title"
                class="w-full px-3 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            <div class="flex gap-3 pt-2">
              <button phx-click="prev_step" class="flex-1 py-2 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors">
                ← Tilbake
              </button>
              <button phx-click="next_step" class="flex-1 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-medium transition-colors">
                Neste →
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Step 3: Theme --%>
        <%= if @step == 3 do %>
          <div class="space-y-6">
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-1">Tema</h2>
              <p class="text-xs text-gray-400 dark:text-gray-500">Kan endres når som helst i innstillinger.</p>
            </div>

            <div class="grid grid-cols-3 gap-3">
              <%= for {value, label, icon} <- [{"light", "Lyst", "☀️"}, {"dark", "Mørkt", "🌙"}, {"system", "Auto", "⚙️"}] do %>
                <button
                  phx-click="set_theme"
                  phx-value-theme={value}
                  class={"p-4 rounded-xl border-2 transition-all text-center #{if @theme == value, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30", else: "border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500"}"}
                >
                  <div class="text-2xl mb-1"><%= icon %></div>
                  <div class="text-sm text-gray-700 dark:text-gray-300"><%= label %></div>
                </button>
              <% end %>
            </div>

            <div class="flex gap-3 pt-2">
              <button phx-click="prev_step" class="flex-1 py-2 text-sm text-gray-500 hover:text-gray-700 transition-colors">
                ← Tilbake
              </button>
              <button phx-click="next_step" class="flex-1 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-medium transition-colors">
                Neste →
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Step 4: Idle + PIN --%>
        <%= if @step == 4 do %>
          <div class="space-y-6">
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-1">Sikkerhet</h2>
              <p class="text-xs text-gray-400 dark:text-gray-500">Appen låses automatisk etter inaktivitet. PIN er valgfritt.</p>
            </div>

            <div>
              <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-2">Lås etter inaktivitet</label>
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

            <div class="space-y-2">
              <label class="block text-xs font-medium text-gray-500 dark:text-gray-400">PIN-kode (valgfritt)</label>
              <input
                type="password"
                name="pin"
                inputmode="numeric"
                placeholder="Minst 4 siffer"
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

            <div class="flex gap-3 pt-2">
              <button phx-click="prev_step" class="flex-1 py-2 text-sm text-gray-500 hover:text-gray-700 transition-colors">
                ← Tilbake
              </button>
              <button phx-click="finish" class="flex-1 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-medium transition-colors">
                Ferdig ✓
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
