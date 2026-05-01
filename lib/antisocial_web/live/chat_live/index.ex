defmodule AntisocialWeb.ChatLive do
  use AntisocialWeb, :live_view

  alias Antisocial.{Accounts, Chat}


  def mount(%{"channel" => slug}, session, socket) do
    user = socket.assigns.current_user

    case Chat.get_or_create_channel(slug) do
      {:ok, channel} ->
        locked = user.pin_hash != nil
        pin_context = if channel.pin_required, do: :channel, else: :app

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Antisocial.PubSub, "channel:#{channel.id}")
          Phoenix.PubSub.subscribe(Antisocial.PubSub, "user:#{user.id}")
        end

        messages = Chat.list_messages(channel.id)
        draft = Chat.get_draft(user.id, channel.id)
        public_channels = Chat.list_public_channels()
        unread = Accounts.unread_notification_count(user.id)

        import Ecto.Query
        all_users = Antisocial.Repo.all(Antisocial.Accounts.User)
        users_map = Map.new(all_users, fn u -> {u.id, u} end)
        other_user = Enum.find(all_users, fn u -> u.id != user.id end)

        if connected?(socket) do
          Enum.each(messages, fn msg -> Chat.mark_first_read(msg, user.id) end)
        end

        {:ok,
         socket
         |> assign(
           channel: channel,
           messages: messages,
           draft_body: (draft && draft.body) || "",
           public_channels: public_channels,
           typing_users: [],
           users_map: users_map,
           locked: locked,
           pin_context: pin_context,
           unread: unread,
           show_create_channel: false,
           new_channel_slug: "",
           new_channel_secret: false,
           idle_minutes: user.idle_minutes || 10,
           view_cleared: false,
           message_menu_id: nil,
           move_to_slug: "",
           ttl_enabled: false,
           ttl_seconds: nil,
           ttl_channel_slug: "",
           session_token: session["session_token"],
           other_user: other_user
         )
         |> allow_upload(:media,
           accept: ~w(image/* video/* audio/*),
           max_entries: 5,
           max_file_size: 200_000_000
         )}

      {:error, _} ->
        {:ok, push_navigate(socket, to: "/chat/generelt")}
    end
  end

  # ── PIN lock ──────────────────────────────────────────────────────────────

  def handle_info({:pin_unlocked, _context}, socket) do
    {:noreply, assign(socket, locked: false)}
  end

  def handle_event("lock", _params, socket) do
    {:noreply, assign(socket, locked: true)}
  end

  def handle_event("panic", _params, socket) do
    # Clear messages from view (session only, no DB change)
    # Lock with PIN if set, otherwise just clear and redirect to generelt
    locked = socket.assigns.current_user.pin_hash != nil
    {:noreply,
     socket
     |> assign(messages: [], view_cleared: true, locked: locked)
     |> push_event("replace_url", %{url: "/chat/generelt"})}
  end

  # ── Messages ──────────────────────────────────────────────────────────────

  def handle_event("save_draft", %{"body" => body}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.channel
    Chat.upsert_draft(user.id, channel.id, body)
    {:noreply, assign(socket, draft_body: body)}
  end

  def handle_event("archive_message", %{"id" => id}, socket) do
    message = Enum.find(socket.assigns.messages, &(&1.id == String.to_integer(id)))
    if message && message.user_id == socket.assigns.current_user.id do
      Chat.archive_message(message)
    end
    {:noreply, socket}
  end

  def handle_event("show_message_menu", %{"id" => id}, socket) do
    {:noreply, assign(socket, message_menu_id: String.to_integer(id), move_to_slug: "")}
  end

  def handle_event("close_message_menu", _params, socket) do
    {:noreply, assign(socket, message_menu_id: nil)}
  end

  def handle_event("update_move_slug", %{"slug" => slug}, socket) do
    {:noreply, assign(socket, move_to_slug: slug)}
  end

  def handle_event("move_message", _params, socket) do
    msg_id = socket.assigns.message_menu_id
    slug = String.trim(socket.assigns.move_to_slug)
    user = socket.assigns.current_user

    with true <- slug != "",
         message when not is_nil(message) <-
           Enum.find(socket.assigns.messages, &(&1.id == msg_id)),
         {:ok, target_channel} <- Chat.get_or_create_channel(slug) do
      Chat.move_message(message, target_channel.id, user.id)
    end

    {:noreply, assign(socket, message_menu_id: nil, move_to_slug: "")}
  end

  # ── Typing ────────────────────────────────────────────────────────────────

  def handle_event("typing_start", _params, socket) do
    Chat.broadcast_typing(socket.assigns.channel.id, socket.assigns.current_user.id, true)
    {:noreply, socket}
  end

  def handle_event("typing_stop", _params, socket) do
    Chat.broadcast_typing(socket.assigns.channel.id, socket.assigns.current_user.id, false)
    {:noreply, socket}
  end

  # ── Notification mode ─────────────────────────────────────────────────────

  def handle_event("set_notification_mode", %{"mode" => mode}, socket) do
    user = socket.assigns.current_user
    {:ok, updated_user} = Accounts.update_settings(user, %{notification_mode: mode})
    socket = assign(socket, current_user: updated_user)
    socket = if mode == "active", do: push_event(socket, "request_notification_permission", %{}), else: socket
    {:noreply, socket}
  end

  # ── Create channel ────────────────────────────────────────────────────────

  def handle_event("toggle_create_channel", _params, socket) do
    {:noreply,
     assign(socket,
       show_create_channel: !socket.assigns.show_create_channel,
       new_channel_slug: "",
       new_channel_secret: false
     )}
  end

  def handle_event("update_channel_slug", %{"slug" => slug}, socket) do
    {:noreply, assign(socket, new_channel_slug: String.downcase(slug))}
  end

  def handle_event("toggle_channel_secret", _params, socket) do
    {:noreply, assign(socket, new_channel_secret: !socket.assigns.new_channel_secret, new_channel_pin: "")}
  end

  def handle_event("join_or_create_channel", %{"slug" => slug}, socket) do
    slug = String.downcase(String.trim(slug))

    if slug != "" do
      Chat.get_or_create_channel(slug, pin_required: socket.assigns.new_channel_secret)

      {:noreply,
       socket
       |> assign(show_create_channel: false, new_channel_slug: "", new_channel_secret: false)
       |> push_navigate(to: "/chat/#{slug}")}
    else
      {:noreply, socket}
    end
  end

  # ── PubSub handlers ───────────────────────────────────────────────────────

  def handle_info({:new_message, message}, socket) do
    Chat.mark_first_read(message, socket.assigns.current_user.id)
    messages = socket.assigns.messages ++ [message]
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:message_archived, id}, socket) do
    messages = Enum.reject(socket.assigns.messages, &(&1.id == id))
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:typing, user_id, true}, socket) do
    typing = [user_id | socket.assigns.typing_users] |> Enum.uniq()
    {:noreply, assign(socket, typing_users: typing)}
  end

  def handle_info({:typing, user_id, false}, socket) do
    typing = Enum.reject(socket.assigns.typing_users, &(&1 == user_id))
    {:noreply, assign(socket, typing_users: typing)}
  end

  def handle_info({:notification, channel_slug}, socket) do
    socket = assign(socket, unread: socket.assigns.unread + 1)
    socket = if socket.assigns.current_user.notification_mode == "active" do
      {title, body} = notification_text(socket.assigns.current_user, channel_slug)
      push_event(socket, "show_notification", %{title: title, body: body})
    else
      socket
    end
    {:noreply, socket}
  end

  # ── WebRTC signaling relay (PubSub → JS hook) ─────────────────────────────

  def handle_info({:webrtc_ring, from_id, from_name}, socket) do
    {:noreply, push_event(socket, "webrtc_ring", %{from_id: from_id, from_name: from_name})}
  end

  def handle_info({:webrtc_accepted, _from_id}, socket) do
    {:noreply, push_event(socket, "webrtc_accepted", %{})}
  end

  def handle_info({:webrtc_offer, sdp, from_id}, socket) do
    {:noreply, push_event(socket, "webrtc_offer", %{sdp: sdp, from_id: from_id})}
  end

  def handle_info({:webrtc_answer, sdp, _from_id}, socket) do
    {:noreply, push_event(socket, "webrtc_answer", %{sdp: sdp})}
  end

  def handle_info({:webrtc_ice, candidate, _from_id}, socket) do
    {:noreply, push_event(socket, "webrtc_ice", %{candidate: candidate})}
  end

  def handle_info({:webrtc_hangup, _from_id}, socket) do
    {:noreply, push_event(socket, "webrtc_hangup", %{})}
  end

  # ── WebRTC signaling relay (JS hook → PubSub) ─────────────────────────────

  def handle_event("webrtc_start_call", %{"to" => to_id_str}, socket) do
    user = socket.assigns.current_user
    to_id = String.to_integer(to_id_str)
    Phoenix.PubSub.broadcast(Antisocial.PubSub, "user:#{to_id}",
      {:webrtc_ring, user.id, user.display_name || user.username})
    {:noreply, socket}
  end

  def handle_event("webrtc_accept_call", %{"to" => to_id_str}, socket) do
    user = socket.assigns.current_user
    to_id = String.to_integer(to_id_str)
    Phoenix.PubSub.broadcast(Antisocial.PubSub, "user:#{to_id}",
      {:webrtc_accepted, user.id})
    {:noreply, socket}
  end

  def handle_event("webrtc_offer", %{"sdp" => sdp, "to" => to_id_str}, socket) do
    user = socket.assigns.current_user
    to_id = String.to_integer(to_id_str)
    Phoenix.PubSub.broadcast(Antisocial.PubSub, "user:#{to_id}",
      {:webrtc_offer, sdp, user.id})
    {:noreply, socket}
  end

  def handle_event("webrtc_answer", %{"sdp" => sdp, "to" => to_id_str}, socket) do
    user = socket.assigns.current_user
    to_id = String.to_integer(to_id_str)
    Phoenix.PubSub.broadcast(Antisocial.PubSub, "user:#{to_id}",
      {:webrtc_answer, sdp, user.id})
    {:noreply, socket}
  end

  def handle_event("webrtc_ice", %{"candidate" => candidate, "to" => to_id_str}, socket) do
    user = socket.assigns.current_user
    to_id = String.to_integer(to_id_str)
    Phoenix.PubSub.broadcast(Antisocial.PubSub, "user:#{to_id}",
      {:webrtc_ice, candidate, user.id})
    {:noreply, socket}
  end

  def handle_event("webrtc_hangup", params, socket) do
    user = socket.assigns.current_user
    case Map.get(params, "to") do
      nil -> :ok
      to_id_str ->
        to_id = String.to_integer(to_id_str)
        Phoenix.PubSub.broadcast(Antisocial.PubSub, "user:#{to_id}",
          {:webrtc_hangup, user.id})
    end
    {:noreply, socket}
  end

  defp notification_text(%{tab_icon: "calculator"}, _slug),
    do: {"Calculation complete", "Result ready"}
  defp notification_text(_, channel_slug),
    do: {"New message", "##{channel_slug}"}

  # ── Geolocation ───────────────────────────────────────────────────────────

  def handle_event("request_geo", _params, socket) do
    {:noreply, push_event(socket, "request_geo", %{})}
  end

  def handle_event("share_location", %{"lat" => lat, "lng" => lng}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.channel

    case Chat.create_message(%{
      user_id: user.id,
      channel_id: channel.id,
      body: "",
      geo_lat: lat,
      geo_lng: lng
    }) do
      {:ok, _} ->
        notify_other_users(user.id, channel)
        {:noreply, socket}
      {:error, _} ->
        {:noreply, socket}
    end
  end

  # ── Media upload ──────────────────────────────────────────────────────────

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("store_fingerprint", fingerprint, socket) do
    if token = socket.assigns[:session_token] do
      Accounts.store_fingerprint(token, fingerprint)
    end
    {:noreply, socket}
  end

  def handle_event("keystroke_sample", %{"intervals" => intervals}, socket) do
    user = socket.assigns.current_user
    Accounts.update_keystroke_profile(user, intervals)
    {:noreply, socket}
  end

  def handle_event("toggle_ttl", _params, socket) do
    {:noreply, assign(socket, ttl_enabled: !socket.assigns.ttl_enabled)}
  end

  def handle_event("set_ttl", %{"seconds" => secs}, socket) do
    {:noreply, assign(socket, ttl_seconds: String.to_integer(secs))}
  end

  def handle_event("set_ttl_channel", %{"ttl_channel" => slug}, socket) do
    {:noreply, assign(socket, ttl_channel_slug: String.downcase(String.trim(slug)))}
  end

  def handle_event("send_with_media", %{"body" => body}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.channel

    uploaded_files =
      consume_uploaded_entries(socket, :media, fn %{path: tmp_path}, entry ->
        ext = Path.extname(entry.client_name)
        filename = "#{Ecto.UUID.generate()}#{ext}"
        rel_path = Chat.storage_rel_path(filename)
        abs_path = Chat.storage_path(filename)
        File.cp!(tmp_path, abs_path)
        {:ok, %{filename: filename, original_filename: entry.client_name, content_type: entry.client_type, file_size: entry.client_size, storage_path: rel_path}}
      end)

    if uploaded_files != [] || String.trim(body) != "" do
      ttl_attrs =
        if socket.assigns.ttl_enabled && socket.assigns.ttl_seconds do
          %{ttl_seconds: socket.assigns.ttl_seconds, ttl_channel_slug: socket.assigns.ttl_channel_slug}
        else
          %{}
        end

      msg_attrs = Map.merge(%{user_id: user.id, channel_id: channel.id, body: String.trim(body)}, ttl_attrs)

      case Chat.create_message(msg_attrs) do
        {:ok, message} ->
          Enum.each(uploaded_files, fn file -> Chat.attach_media(message.id, file) end)
          Chat.upsert_draft(user.id, channel.id, "")
          notify_other_users(user.id, channel)
          {:noreply, assign(socket, draft_body: "", ttl_enabled: false, ttl_seconds: nil, ttl_channel_slug: "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not send message.")}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp notify_other_users(sender_id, channel) do
    import Ecto.Query
    users = Antisocial.Repo.all(
      from u in Antisocial.Accounts.User,
        where: u.id != ^sender_id and u.notification_mode == "active"
    )
    Enum.each(users, fn user ->
      Accounts.create_notification(user.id)
      Phoenix.PubSub.broadcast(Antisocial.PubSub, "user:#{user.id}", {:notification, channel.slug})
    end)
  end

  def render(assigns) do
    ~H"""
    <div id="chat-theme-root" phx-hook="ThemeHook" data-theme={@current_user.theme} class="hidden" />
    <div id="pin-lock-watcher" phx-hook="PinLock" data-idle-minutes={@idle_minutes} class="hidden" />
    <div id="notifications-hook" phx-hook="Notifications" class="hidden" />
    <div id="fingerprint-hook" phx-hook="DeviceFingerprint" class="hidden" />
    <div id="webrtc-hook" phx-hook="WebRTCHook" class="hidden" />

    <%= if @locked do %>
      <.live_component
        module={AntisocialWeb.PinLockComponent}
        id="pin-lock"
        current_user={@current_user}
        context={@pin_context}
      />
    <% end %>

    <div class={"flex h-screen bg-white dark:bg-gray-900 #{if @locked, do: "pointer-events-none select-none blur-sm"}"}>
      <%!-- Sidebar --%>
      <aside class="w-56 flex-shrink-0 bg-gray-50 dark:bg-gray-800 border-r border-gray-200 dark:border-gray-700 flex flex-col">
        <div class="p-4 border-b border-gray-200 dark:border-gray-700">
          <%!-- Double-click or Alt+Shift+X triggers panic flush — no visible hint --%>
          <p
            id="channel-header"
            phx-hook="PanicButton"
            class="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500 select-none cursor-default"
          >Channels</p>
        </div>

        <nav class="flex-1 overflow-y-auto p-2 space-y-0.5">
          <%= for ch <- @public_channels do %>
            <.link
              navigate={~p"/chat/#{ch.slug}"}
              class={"flex items-center px-3 py-1.5 rounded-lg text-sm transition-colors #{if ch.id == @channel.id, do: "bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 font-medium", else: "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"}"}
            >
              # <%= ch.slug %>
            </.link>
          <% end %>
        </nav>

        <div class="p-3 border-t border-gray-200 dark:border-gray-700 space-y-2">
          <button
            phx-click="toggle_create_channel"
            class="w-full text-left px-3 py-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
          >
            + New channel
          </button>

          <%= if @show_create_channel do %>
            <form phx-submit="join_or_create_channel" class="space-y-2">
              <input
                type="text"
                name="slug"
                value={@new_channel_slug}
                phx-change="update_channel_slug"
                placeholder="kanalnavn"
                autofocus
                class="w-full px-2 py-1.5 text-sm rounded border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-1 focus:ring-blue-500"
              />
              <%!-- Public / Secret toggle --%>
              <div class="flex gap-1">
                <button
                  type="button"
                  phx-click="toggle_channel_secret"
                  class={"flex-1 py-1 text-xs rounded border transition-colors #{if !@new_channel_secret, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300", else: "border-gray-200 dark:border-gray-600 text-gray-500 dark:text-gray-400 hover:border-gray-300"}"}
                >
                  🌐 Public
                </button>
                <button
                  type="button"
                  phx-click="toggle_channel_secret"
                  class={"flex-1 py-1 text-xs rounded border transition-colors #{if @new_channel_secret, do: "border-blue-500 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300", else: "border-gray-200 dark:border-gray-600 text-gray-500 dark:text-gray-400 hover:border-gray-300"}"}
                >
                  🔒 Secret
                </button>
              </div>
              <%= if @new_channel_secret do %>
                <p class="text-xs text-gray-400 dark:text-gray-500 leading-snug">
                  Hidden from the sidebar. Requires PIN and channel slug to access.
                </p>
              <% end %>
              <button type="submit" class="w-full py-1.5 text-xs bg-blue-600 hover:bg-blue-700 text-white rounded transition-colors">
                <%= if @new_channel_slug == "" do %>Go to channel<% else %><%= if @new_channel_secret, do: "Create secret ##{@new_channel_slug}", else: "Go to / create ##{@new_channel_slug}" %><% end %>
              </button>
            </form>
          <% end %>

          <.link navigate={~p"/bulletin"} class="block px-3 py-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors">
            📌 Bulletin board
          </.link>
        </div>

        <%!-- User + settings footer --%>
        <div class="p-3 border-t border-gray-200 dark:border-gray-700">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 min-w-0">
              <img
                src={if @current_user.avatar_path, do: "/media/#{@current_user.avatar_path}", else: gravatar_url(@current_user.username)}
                class="w-6 h-6 rounded-full object-cover flex-shrink-0"
                alt={@current_user.username}
              />
              <span class="text-sm font-medium text-gray-700 dark:text-gray-300 truncate">
                <%= @current_user.username %>
              </span>
            </div>
            <div class="flex items-center gap-1">
              <%= if @unread > 0 do %>
                <span class="px-1.5 py-0.5 text-xs bg-blue-600 text-white rounded-full font-medium">
                  <%= @unread %>
                </span>
              <% end %>
              <.link navigate={~p"/settings"} class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 transition-colors" title="Innstillinger">
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
              </.link>
            </div>
          </div>
        </div>
      </aside>

      <%!-- Main chat area --%>
      <main class="flex-1 flex flex-col min-w-0">
        <%!-- Notification mode banner --%>
        <div class="flex items-center gap-4 px-4 py-2 bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 text-sm">
          <span class="text-gray-500 dark:text-gray-400">Notifications:</span>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              type="radio"
              name="notification_mode"
              value="active"
              checked={@current_user.notification_mode == "active"}
              phx-click="set_notification_mode"
              phx-value-mode="active"
              class="text-blue-600"
            />
            <span class="text-gray-700 dark:text-gray-300">Active</span>
          </label>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              type="radio"
              name="notification_mode"
              value="stealth"
              checked={@current_user.notification_mode == "stealth"}
              phx-click="set_notification_mode"
              phx-value-mode="stealth"
              class="text-blue-600"
            />
            <span class="text-gray-700 dark:text-gray-300">Silent</span>
          </label>
          <div class="ml-auto flex items-center gap-2">
            <span class="text-gray-400 dark:text-gray-500 font-mono text-xs">#<%= @channel.slug %></span>
            <%= if @other_user do %>
              <button
                phx-click="webrtc_start_call"
                phx-value-to={@other_user.id}
                class="p-1.5 text-gray-400 hover:text-green-500 dark:hover:text-green-400 transition-colors rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"
                title={"Call #{@other_user.username}"}
              >
                <.icon name="hero-phone" class="w-4 h-4" />
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Messages --%>
        <div
          id="messages"
          phx-hook="ScrollBottom"
          class="flex-1 overflow-y-auto px-4 py-4 space-y-3"
        >
          <%= for msg <- @messages do %>
            <div id={"msg-#{msg.id}"} data-msg-id={msg.id} phx-hook="MessageContext" class="group flex items-start gap-3">
              <img
                src={if msg.user.avatar_path, do: "/media/#{msg.user.avatar_path}", else: gravatar_url(msg.user.username)}
                class="flex-shrink-0 w-8 h-8 rounded-full object-cover"
                alt={msg.user.username}
              />
              <div class="flex-1 min-w-0">
                <div class="flex items-baseline gap-2 mb-0.5">
                  <span class="text-sm font-semibold text-gray-900 dark:text-white"><%= msg.user.username %></span>
                  <span class="text-xs text-gray-400 dark:text-gray-500"><%= format_time(msg.inserted_at) %></span>
                  <%= if msg.user_id == @current_user.id do %>
                    <button
                      phx-click="archive_message"
                      phx-value-id={msg.id}
                      class="ml-auto opacity-0 group-hover:opacity-100 text-xs text-gray-400 hover:text-red-500 transition-all"
                    >
                      delete
                    </button>
                  <% end %>
                </div>
                <%= if msg.body != "" do %>
                  <p class="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap break-words"><%= msg.body %></p>
                <% end %>

                <%!-- Geo attachment --%>
                <%= if msg.geo_lat && msg.geo_lng do %>
                  <a
                    href={"https://www.openstreetmap.org/?mlat=#{msg.geo_lat}&mlon=#{msg.geo_lng}&zoom=16&layers=M"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="mt-1 inline-flex items-center gap-2 px-3 py-2 rounded-xl bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 text-green-700 dark:text-green-400 text-sm hover:bg-green-100 dark:hover:bg-green-900/40 transition-colors"
                  >
                    <.icon name="hero-map-pin" class="w-4 h-4 flex-shrink-0" />
                    <span>Location — tap to open</span>
                  </a>
                <% end %>

                <%!-- TTL badge --%>
                <%= if msg.ttl_seconds do %>
                  <span class="inline-flex items-center gap-1 text-xs text-amber-600 dark:text-amber-400 mt-0.5">
                    <.icon name="hero-clock" class="w-3 h-3" />
                    <%= ttl_label(msg.ttl_seconds) %>
                    <%= if msg.ttl_channel_slug && msg.ttl_channel_slug != "", do: "→ ##{msg.ttl_channel_slug}", else: "" %>
                  </span>
                <% end %>

                <%!-- Media attachments — images in grid, video/audio inline --%>
                <% images = Enum.filter(msg.media_attachments, &Antisocial.Chat.MediaAttachment.image?/1) %>
                <% non_images = Enum.reject(msg.media_attachments, &Antisocial.Chat.MediaAttachment.image?/1) %>
                <%= if images != [] do %>
                  <div class={"mt-2 grid gap-1 #{if length(images) == 1, do: "grid-cols-1 max-w-xs", else: "grid-cols-2 max-w-sm"}"}>
                    <%= for attachment <- images do %>
                      <img
                        src={"/media/#{attachment.storage_path}"}
                        alt={attachment.original_filename}
                        loading="lazy"
                        class="rounded-lg w-full h-32 object-cover cursor-pointer hover:opacity-90"
                      />
                    <% end %>
                  </div>
                <% end %>
                <%= for attachment <- non_images do %>
                  <div class="mt-2 max-w-sm">
                    <%= if Antisocial.Chat.MediaAttachment.video?(attachment) do %>
                      <video
                        src={"/media/#{attachment.storage_path}"}
                        controls
                        preload="metadata"
                        class="rounded-lg max-w-full max-h-64"
                      />
                    <% else %>
                      <audio
                        src={"/media/#{attachment.storage_path}"}
                        controls
                        preload="metadata"
                        class="w-full max-w-xs mt-1"
                      />
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Typing indicator --%>
          <%= if @typing_users != [] do %>
            <div class="flex items-center gap-2 text-xs text-gray-400 dark:text-gray-500">
              <div class="flex gap-0.5 items-center">
                <span class="w-1.5 h-1.5 rounded-full bg-gray-400 dark:bg-gray-500 animate-bounce" style="animation-delay: 0ms" />
                <span class="w-1.5 h-1.5 rounded-full bg-gray-400 dark:bg-gray-500 animate-bounce" style="animation-delay: 150ms" />
                <span class="w-1.5 h-1.5 rounded-full bg-gray-400 dark:bg-gray-500 animate-bounce" style="animation-delay: 300ms" />
              </div>
              <%= @typing_users
                  |> Enum.map(fn uid -> Map.get(@users_map, uid) end)
                  |> Enum.reject(&is_nil/1)
                  |> Enum.map(& &1.username)
                  |> Enum.join(", ")
              %> typing...
            </div>
          <% end %>
        </div>

        <%!-- Composer --%>
        <div class="border-t border-gray-200 dark:border-gray-700 p-3">
          <form phx-submit="send_with_media" phx-change="validate_upload" class="space-y-2">
            <%!-- TTL options --%>
            <%= if @ttl_enabled do %>
              <div class="flex flex-wrap items-center gap-2 px-1 text-xs">
                <span class="text-gray-500 dark:text-gray-400">Disappear after read:</span>
                <%= for {secs, label} <- [{300, "5m"}, {3600, "1h"}, {86400, "24h"}] do %>
                  <button
                    type="button"
                    phx-click="set_ttl"
                    phx-value-seconds={secs}
                    class={"px-2 py-0.5 rounded-lg border transition-colors #{if @ttl_seconds == secs, do: "border-amber-500 bg-amber-50 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300", else: "border-gray-200 dark:border-gray-600 text-gray-500 dark:text-gray-400 hover:border-gray-300"}"}
                  >
                    <%= label %>
                  </button>
                <% end %>
                <span class="text-gray-400">→</span>
                <input
                  type="text"
                  placeholder="channel (blank = archive)"
                  value={@ttl_channel_slug}
                  phx-change="set_ttl_channel"
                  name="ttl_channel"
                  class="w-36 px-2 py-0.5 text-xs rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:outline-none focus:ring-1 focus:ring-amber-500"
                />
              </div>
            <% end %>
            <%!-- Upload previews --%>
            <%= if Enum.any?(@uploads.media.entries) do %>
              <div class="flex flex-wrap gap-2 mb-2">
                <%= for entry <- @uploads.media.entries do %>
                  <div class="relative group">
                    <%= if String.starts_with?(entry.client_type, "image/") do %>
                      <.live_img_preview entry={entry} class="h-16 w-16 object-cover rounded-lg" />
                    <% else %>
                      <div class="h-16 w-16 rounded-lg bg-gray-100 dark:bg-gray-700 flex items-center justify-center text-xs text-gray-500">
                        <%= Path.extname(entry.client_name) %>
                      </div>
                    <% end %>
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      class="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-red-500 text-white text-xs flex items-center justify-center opacity-0 group-hover:opacity-100"
                    >×</button>
                    <div class="w-full mt-1 h-1 bg-gray-200 dark:bg-gray-600 rounded-full overflow-hidden">
                      <div class="h-full bg-blue-500 transition-all" style={"width: #{entry.progress}%"} />
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>

            <div class="flex items-end gap-2">
              <label class="cursor-pointer p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 transition-colors">
                <.live_file_input upload={@uploads.media} class="hidden" />
                <.icon name="hero-paper-clip" class="w-5 h-5" />
              </label>
              <button
                type="button"
                phx-click="request_geo"
                class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 transition-colors"
                title="Share location"
              >
                <.icon name="hero-map-pin" class="w-5 h-5" />
              </button>
              <button
                type="button"
                phx-click="toggle_ttl"
                class={"p-2 transition-colors #{if @ttl_enabled, do: "text-amber-500 hover:text-amber-600", else: "text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"}"}
                title="Set message TTL"
              >
                <.icon name="hero-clock" class="w-5 h-5" />
              </button>
              <button
                type="button"
                id="voice-record-btn"
                phx-hook="VoiceRecorder"
                class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 transition-colors touch-none"
                title="Hold to record voice message"
              >
                <.icon name="hero-microphone" class="w-5 h-5" />
              </button>

              <textarea
                id="composer"
                name="body"
                value={@draft_body}
                phx-hook="ComposerHook"
                rows="1"
                placeholder="Write something..."
                class="flex-1 resize-none px-3 py-2 rounded-xl border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 text-sm max-h-40 overflow-y-auto"
              />

              <button
                type="submit"
                class="p-2 bg-blue-600 hover:bg-blue-700 text-white rounded-xl transition-colors flex-shrink-0"
              >
                <.icon name="hero-paper-airplane" class="w-5 h-5" />
              </button>
            </div>
          </form>
        </div>
      </main>
    </div>

    <%!-- Move-to-channel modal --%>
    <%= if @message_menu_id do %>
      <div
        class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 bg-black/40"
        phx-click="close_message_menu"
      >
        <div
          class="w-full max-w-sm bg-white dark:bg-gray-800 rounded-2xl p-5 space-y-4 shadow-xl"
          phx-click-away="close_message_menu"
        >
          <div>
            <h3 class="text-sm font-semibold text-gray-900 dark:text-white">Move message</h3>
            <p class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
              Enter the channel name to move the message to. Channel will be created if it doesn't exist.
            </p>
          </div>
          <input
            type="text"
            placeholder="channel name (e.g. secret)"
            value={@move_to_slug}
            phx-change="update_move_slug"
            name="slug"
            autofocus
            class="w-full px-3 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <div class="flex gap-2">
            <button
              phx-click="close_message_menu"
              class="flex-1 py-2 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="move_message"
              class="flex-1 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-medium transition-colors"
            >
              Move →
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp gravatar_url(username) do
    hash = :crypto.hash(:md5, String.downcase(username)) |> Base.encode16(case: :lower)
    "https://www.gravatar.com/avatar/#{hash}?d=identicon&s=80"
  end

  defp ttl_label(secs) when secs < 3600, do: "#{div(secs, 60)}m TTL"
  defp ttl_label(secs) when secs < 86400, do: "#{div(secs, 3600)}h TTL"
  defp ttl_label(secs), do: "#{div(secs, 86400)}d TTL"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end
  defp format_time(_), do: ""

  defp avatar_color(username) do
    colors = [
      "bg-red-200 text-red-800",
      "bg-orange-200 text-orange-800",
      "bg-amber-200 text-amber-800",
      "bg-green-200 text-green-800",
      "bg-teal-200 text-teal-800",
      "bg-blue-200 text-blue-800",
      "bg-indigo-200 text-indigo-800",
      "bg-purple-200 text-purple-800",
      "bg-pink-200 text-pink-800"
    ]
    Enum.at(colors, :erlang.phash2(username, length(colors)))
  end

end
