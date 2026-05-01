defmodule AntisocialWeb.SettingsLive do
  use AntisocialWeb, :live_view

  alias Antisocial.{Accounts, Repo}
  import Ecto.Query

  @icons [
    %{id: "bubbles_chat", label: "Chat"},
    %{id: "calculator", label: "Calculator"},
    %{id: "google", label: "Google"},
    %{id: "science", label: "Science"},
    %{id: "molecule_physics", label: "Physics"},
    %{id: "terminal", label: "Terminal"},
    %{id: "dns", label: "DNS"},
    %{id: "cms_admin", label: "Admin"},
    %{id: "development", label: "Dev"},
    %{id: "tech-chip", label: "Tech"},
    %{id: "cat_chat", label: "Cat"},
    %{id: "banana", label: "Banana"},
    %{id: "cannabis", label: "Herb"},
  ]

  def mount(_params, session, socket) do
    user = socket.assigns.current_user
    other_users = Repo.all(from u in Accounts.User, where: u.id != ^user.id)
    sessions = Accounts.list_sessions(user.id)
    current_token = session["session_token"]

    aliases =
      Enum.map(other_users, fn u ->
        {u, Map.get(user.contact_aliases || %{}, to_string(u.id), "")}
      end)

    passkeys = Accounts.list_passkeys(user.id)

    {:ok,
     socket
     |> assign(
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
       saved: false,
       login_token: nil,
       user_sessions: sessions,
       current_session_token: current_token,
       passkeys: passkeys,
       passkey_error: nil,
       tap_count: 0,
       show_debug: false,
       all_channels: []
     )
     |> allow_upload(:avatar, accept: ~w(image/*), max_entries: 1, max_file_size: 5_000_000)}
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

  def handle_event("update_pin_confirm", %{"pin_confirm" => pin}, socket) do
    {:noreply, assign(socket, pin_confirm: pin, saved: false)}
  end

  def handle_event("version_tap", _params, socket) do
    count = socket.assigns.tap_count + 1
    if count >= 5 do
      all_channels = Antisocial.Chat.list_all_channels()
      {:noreply, assign(socket, tap_count: 0, show_debug: true, all_channels: all_channels)}
    else
      {:noreply, assign(socket, tap_count: count)}
    end
  end

  def handle_event("passkey_registered", _params, socket) do
    passkeys = Accounts.list_passkeys(socket.assigns.current_user.id)
    {:noreply, assign(socket, passkeys: passkeys, passkey_error: nil)}
  end

  def handle_event("passkey_error", %{"message" => msg}, socket) do
    {:noreply, assign(socket, passkey_error: msg)}
  end

  def handle_event("delete_passkey", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    Accounts.delete_passkey(user.id, String.to_integer(id))
    passkeys = Accounts.list_passkeys(user.id)
    {:noreply, assign(socket, passkeys: passkeys)}
  end

  def handle_event("revoke_session", %{"token" => token}, socket) do
    user = socket.assigns.current_user
    # Only revoke sessions belonging to this user
    sessions = socket.assigns.user_sessions
    if Enum.any?(sessions, &(&1.token == token)) do
      Accounts.delete_session(token)
      updated = Accounts.list_sessions(user.id)
      {:noreply, assign(socket, user_sessions: updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("revoke_all_other_sessions", _params, socket) do
    user = socket.assigns.current_user
    current_token = socket.assigns.current_session_token
    # Delete all sessions except current
    import Ecto.Query
    Antisocial.Repo.delete_all(
      from s in Antisocial.Accounts.UserSession,
        where: s.user_id == ^user.id and s.token != ^current_token
    )
    updated = Accounts.list_sessions(user.id)
    {:noreply, assign(socket, user_sessions: updated)}
  end

  def handle_event("generate_login_token", _params, socket) do
    user = socket.assigns.current_user

    case Accounts.create_login_token(user) do
      {:ok, token} ->
        {:noreply, assign(socket, login_token: token)}
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("dismiss_login_token", _params, socket) do
    {:noreply, assign(socket, login_token: nil)}
  end

  def handle_event("validate_avatar", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_avatar", _params, socket) do
    user = socket.assigns.current_user

    paths =
      consume_uploaded_entries(socket, :avatar, fn %{path: tmp_path}, entry ->
        ext = Path.extname(entry.client_name)
        filename = "avatars/#{Ecto.UUID.generate()}#{ext}"
        dest = Path.join(Antisocial.Chat.upload_dir(), filename)
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(tmp_path, dest)
        {:ok, filename}
      end)

    case paths do
      [filename] ->
        Accounts.update_avatar(user, filename)
        {:noreply, assign(socket, saved: true)}
      _ ->
        {:noreply, socket}
    end
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

  defp gravatar_url(username) do
    hash = :crypto.hash(:md5, String.downcase(username)) |> Base.encode16(case: :lower)
    "https://www.gravatar.com/avatar/#{hash}?d=identicon&s=80"
  end

  defp format_time_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp avatar_color(username) do
    colors = ["bg-red-200 text-red-800", "bg-orange-200 text-orange-800", "bg-amber-200 text-amber-800", "bg-green-200 text-green-800", "bg-teal-200 text-teal-800", "bg-blue-200 text-blue-800", "bg-indigo-200 text-indigo-800", "bg-purple-200 text-purple-800", "bg-pink-200 text-pink-800"]
    Enum.at(colors, :erlang.phash2(username, length(colors)))
  end

  defp validate_pin("", _), do: :ok
  defp validate_pin(p, p) when byte_size(p) >= 4, do: :ok
  defp validate_pin(p, p), do: {:error, "PIN must be at least 4 characters."}
  defp validate_pin(_, _), do: {:error, "PINs do not match."}

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
          <h1 class="text-xl font-semibold text-gray-900 dark:text-white">Settings</h1>
          <.link navigate={~p"/chat/generelt"} class="text-sm text-gray-400 hover:text-gray-600 dark:hover:text-gray-200">
            ← Back
          </.link>
        </div>

        <%!-- Avatar --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Profile picture</h2>
          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 border border-gray-100 dark:border-gray-700">
            <div class="flex items-center gap-4">
              <%!-- Current avatar preview --%>
              <img
                src={if @current_user.avatar_path, do: "/media/#{@current_user.avatar_path}", else: gravatar_url(@current_user.username)}
                class="w-16 h-16 rounded-full object-cover flex-shrink-0"
                alt="avatar"
              />
              <div class="flex-1">
                <form phx-submit="save_avatar" phx-change="validate_avatar" class="space-y-2">
                  <label class="block text-sm text-gray-600 dark:text-gray-400 cursor-pointer">
                    <.live_file_input upload={@uploads.avatar} class="hidden" />
                    <span class="px-3 py-1.5 text-xs rounded-lg border border-gray-200 dark:border-gray-600 hover:border-gray-400 transition-colors cursor-pointer">
                      Choose image...
                    </span>
                  </label>
                  <%= for entry <- @uploads.avatar.entries do %>
                    <div class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                      <.live_img_preview entry={entry} class="w-8 h-8 rounded-full object-cover" />
                      <span class="truncate max-w-[160px]"><%= entry.client_name %></span>
                      <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-gray-400 hover:text-red-500">×</button>
                    </div>
                    <div class="w-full h-1 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
                      <div class="h-full bg-blue-500 transition-all" style={"width: #{entry.progress}%"} />
                    </div>
                  <% end %>
                  <%= if @uploads.avatar.entries != [] do %>
                    <button type="submit" class="px-3 py-1.5 text-xs bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors">
                      Upload
                    </button>
                  <% end %>
                </form>
              </div>
            </div>
          </div>
        </section>

        <%!-- Appearance --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Appearance</h2>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-5 border border-gray-100 dark:border-gray-700">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">Theme</label>
              <div class="flex gap-3">
                <%= for {value, label, icon} <- [{"light", "Light", "☀️"}, {"dark", "Dark", "🌙"}, {"system", "Auto", "⚙️"}] do %>
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
          <div>
            <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Tab disguise</h2>
            <p class="text-xs text-gray-400 dark:text-gray-500 mt-1">
              Controls what's shown in the browser tab, app switcher, and when saved to home screen. Change this if your situation changes.
            </p>
          </div>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-5 border border-gray-100 dark:border-gray-700">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">Icon</label>
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
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Tab title</label>
              <input
                type="text"
                name="title"
                value={@tab_title}
                phx-change="update_title"
                class="w-full px-3 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <p class="text-xs text-gray-400 mt-1">Shown in the browser tab and when saved to home screen.</p>
            </div>
          </div>
        </section>

        <%!-- Contact aliases --%>
        <%= if @contact_aliases != [] do %>
          <section class="space-y-4">
            <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Contact names</h2>
            <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 border border-gray-100 dark:border-gray-700">
              <p class="text-xs text-gray-400 dark:text-gray-500 mb-4">
                Customize how contacts appear in chat — only visible to you.
              </p>
              <div class="space-y-3">
                <%= for {user, alias_val} <- @contact_aliases do %>
                  <div class="flex items-center gap-3">
                    <div class="w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900 flex items-center justify-center text-sm font-semibold text-blue-700 dark:text-blue-300 flex-shrink-0">
                      <%= String.first(user.username) |> String.upcase() %>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="text-xs text-gray-400 dark:text-gray-500 mb-0.5">Original: <span class="font-mono"><%= user.username %></span></p>
                      <input
                        type="text"
                        placeholder={"Show as... (e.g. Tore)"}
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
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Notifications & lock</h2>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-5 border border-gray-100 dark:border-gray-700">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Notifications</label>
              <div class="flex gap-3">
                <%= for {value, label} <- [{"active", "Active"}, {"stealth", "Silent"}] do %>
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
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Lock after inactivity</label>
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
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">PIN code</h2>

          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-3 border border-gray-100 dark:border-gray-700">
            <%= if @current_user.pin_hash do %>
              <p class="text-sm text-gray-500 dark:text-gray-400">PIN is set. Enter a new PIN to change it, or clear it.</p>
              <button phx-click="clear_pin" class="text-sm text-red-500 hover:text-red-600">Clear PIN</button>
            <% else %>
              <p class="text-sm text-gray-500 dark:text-gray-400">No PIN set. Add one for extra protection.</p>
            <% end %>
            <input
              type="password"
              name="pin"
              inputmode="numeric"
              placeholder="New PIN (min 4 chars)"
              value={@pin}
              phx-change="update_pin"
              class="w-full px-3 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <%= if @pin != "" do %>
              <input
                type="password"
                name="pin_confirm"
                inputmode="numeric"
                placeholder="Confirm PIN"
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

        <%!-- Active sessions --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Active sessions</h2>
          <div class="bg-white dark:bg-gray-800 rounded-2xl border border-gray-100 dark:border-gray-700 overflow-hidden">
            <%= for s <- @user_sessions do %>
              <div class="flex items-center gap-3 px-5 py-3 border-b border-gray-100 dark:border-gray-700 last:border-0">
                <div class="flex-1 min-w-0">
                  <p class="text-xs text-gray-500 dark:text-gray-400 truncate">
                    <%= if s.user_agent do %>
                      <%= s.user_agent |> String.slice(0, 60) %>
                    <% else %>
                      Unknown device
                    <% end %>
                  </p>
                  <p class="text-xs text-gray-400 dark:text-gray-500">
                    <%= if s.ip_addr, do: s.ip_addr, else: "—" %>
                    <%= if s.last_seen_at, do: " · #{format_time_ago(s.last_seen_at)}", else: "" %>
                    <%= if s.fingerprint && s.fingerprint["fp_id"] do %>
                      · <span class="font-mono"><%= s.fingerprint["fp_id"] %></span>
                    <% end %>
                  </p>
                </div>
                <%= if s.token == @current_session_token do %>
                  <span class="text-xs text-green-500 font-medium flex-shrink-0">current</span>
                <% else %>
                  <button
                    phx-click="revoke_session"
                    phx-value-token={s.token}
                    class="text-xs text-red-400 hover:text-red-600 flex-shrink-0"
                  >
                    revoke
                  </button>
                <% end %>
              </div>
            <% end %>
            <%= if length(@user_sessions) > 1 do %>
              <div class="px-5 py-3 border-t border-gray-100 dark:border-gray-700">
                <button phx-click="revoke_all_other_sessions" class="text-xs text-red-400 hover:text-red-600">
                  Revoke all other sessions
                </button>
              </div>
            <% end %>
          </div>
        </section>

        <%!-- Device login --%>
        <section class="space-y-4">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Log in on another device</h2>
          <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-3 border border-gray-100 dark:border-gray-700">
            <p class="text-xs text-gray-400 dark:text-gray-500">
              Generate a one-time code (valid 15 minutes) to log in on another device without a password.
            </p>
            <%= if @login_token do %>
              <div class="space-y-3">
                <div class="flex items-center justify-center">
                  <span class="text-4xl font-mono font-bold tracking-widest text-gray-900 dark:text-white select-all">
                    <%= @login_token.device_code %>
                  </span>
                </div>
                <p class="text-xs text-center text-gray-400 dark:text-gray-500">
                  Enter this code + your username on the other device's login page.
                </p>
                <p class="text-xs text-center text-gray-400 dark:text-gray-500 font-mono break-all">
                  Or use the link: /invite/<%= @login_token.token %>
                </p>
                <button phx-click="dismiss_login_token" class="w-full text-xs text-gray-400 hover:text-gray-600 py-1">
                  Dismiss
                </button>
              </div>
            <% else %>
              <button
                phx-click="generate_login_token"
                class="px-4 py-2 text-sm bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-300 rounded-lg transition-colors"
              >
                Generate device code
              </button>
            <% end %>
          </div>
        </section>

        <%!-- Passkeys --%>
        <section class="space-y-4" id="passkey-section" phx-hook="PasskeyRegister">
          <div>
            <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Passkeys</h2>
            <p class="text-xs text-gray-400 dark:text-gray-500 mt-1">
              Log in with Face ID, Touch ID, or a security key — no password needed.
            </p>
          </div>

          <div class="bg-white dark:bg-gray-800 rounded-2xl border border-gray-100 dark:border-gray-700 overflow-hidden">
            <%= for pk <- @passkeys do %>
              <div class="flex items-center gap-3 px-5 py-3 border-b border-gray-100 dark:border-gray-700 last:border-0">
                <div class="flex-1 min-w-0">
                  <p class="text-sm text-gray-700 dark:text-gray-300"><%= pk.label %></p>
                  <p class="text-xs text-gray-400 dark:text-gray-500">
                    Added <%= format_time_ago(pk.inserted_at) %>
                    <%= if pk.aaguid, do: " · #{pk.aaguid |> String.slice(0, 8)}", else: "" %>
                  </p>
                </div>
                <button
                  phx-click="delete_passkey"
                  phx-value-id={pk.id}
                  class="text-xs text-red-400 hover:text-red-600 flex-shrink-0"
                >
                  remove
                </button>
              </div>
            <% end %>
            <div class="px-5 py-4">
              <%= if @passkey_error do %>
                <p class="text-xs text-red-400 mb-2"><%= @passkey_error %></p>
              <% end %>
              <button
                id="add-passkey-btn"
                class="px-4 py-2 text-sm bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-300 rounded-lg transition-colors"
              >
                + Add passkey
              </button>
            </div>
          </div>
        </section>

        <%!-- Keystroke profile --%>
        <%= if @current_user.keystroke_profile && @current_user.keystroke_profile["n"] > 0 do %>
          <section class="space-y-4">
            <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Typing profile</h2>
            <div class="bg-white dark:bg-gray-800 rounded-2xl p-5 border border-gray-100 dark:border-gray-700">
              <p class="text-xs text-gray-500 dark:text-gray-400">
                Samples: <%= @current_user.keystroke_profile["n"] %> keystrokes ·
                Avg interval: <%= (@current_user.keystroke_profile["mean"] || 0) |> round() %>ms ·
                Std dev: <%= (:math.sqrt(max(@current_user.keystroke_profile["variance"] || 0, 0))) |> round() %>ms
              </p>
              <p class="text-xs text-gray-400 dark:text-gray-500 mt-1">
                Your typing rhythm is being learned. Unusual access attempts will be flagged.
              </p>
            </div>
          </section>
        <% end %>

        <%!-- Save --%>
        <div class="flex items-center gap-4">
          <button
            phx-click="save"
            class="px-6 py-2.5 bg-blue-600 hover:bg-blue-700 text-white rounded-xl font-medium text-sm transition-colors"
          >
            Save settings
          </button>
          <%= if @saved do %>
            <span class="text-sm text-green-500">✓ Saved</span>
          <% end %>
        </div>

        <%!-- Debug panel (unlocked by tapping version 5 times) --%>
        <%= if @show_debug do %>
          <section class="space-y-4 pb-8">
            <h2 class="text-xs font-semibold uppercase tracking-wider text-orange-400">Debug</h2>
            <div class="bg-white dark:bg-gray-800 rounded-2xl border border-orange-200 dark:border-orange-800 overflow-hidden">
              <div class="px-5 py-3 border-b border-gray-100 dark:border-gray-700">
                <p class="text-xs font-mono text-gray-500 dark:text-gray-400">
                  antisocial v<%= Application.spec(:antisocial, :vsn) |> to_string() %>
                  &nbsp;·&nbsp;
                  elixir <%= System.version() %>
                </p>
              </div>
              <div class="px-5 py-3 border-b border-gray-100 dark:border-gray-700">
                <p class="text-xs font-semibold text-gray-500 dark:text-gray-400 mb-2">All channels (<%= length(@all_channels) %>)</p>
                <div class="space-y-1">
                  <%= for ch <- @all_channels do %>
                    <.link
                      navigate={~p"/chat/#{ch.slug}"}
                      class="flex items-center gap-2 text-sm text-blue-600 dark:text-blue-400 hover:underline"
                    >
                      <span class="font-mono">#<%= ch.slug %></span>
                      <%= if ch.pin_required do %>
                        <span class="text-xs px-1.5 py-0.5 rounded bg-orange-100 dark:bg-orange-900/40 text-orange-600 dark:text-orange-400">secret</span>
                      <% end %>
                    </.link>
                  <% end %>
                </div>
              </div>
              <div class="px-5 py-3">
                <p class="text-xs font-mono text-gray-400 dark:text-gray-500">node: <%= node() %></p>
              </div>
            </div>
          </section>
        <% end %>

        <%!-- Version footer — tap 5 times to unlock debug panel --%>
        <div class="pb-8 text-center">
          <button
            phx-click="version_tap"
            class="text-xs text-gray-300 dark:text-gray-700 select-none"
            tabindex="-1"
          >
            v<%= Application.spec(:antisocial, :vsn) |> to_string() %>
            <%= if @tap_count > 0 and not @show_debug do %>
              <span class="text-orange-400">(<%= 5 - @tap_count %> more)</span>
            <% end %>
          </button>
        </div>
      </div>
    </div>
    """
  end
end
