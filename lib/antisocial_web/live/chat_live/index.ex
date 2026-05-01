defmodule AntisocialWeb.ChatLive do
  use AntisocialWeb, :live_view

  alias Antisocial.{Accounts, Chat}

  @idle_minutes Application.compile_env(:antisocial, :idle_lock_minutes, 10)

  def mount(%{"channel" => slug}, _session, socket) do
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

        {:ok,
         socket
         |> assign(
           channel: channel,
           messages: messages,
           draft_body: (draft && draft.body) || "",
           public_channels: public_channels,
           typing_users: [],
           locked: locked,
           pin_context: pin_context,
           unread: unread,
           show_create_channel: false,
           new_channel_slug: "",
           idle_minutes: idle_minutes(),
           view_cleared: false
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

  def handle_event("send_message", %{"body" => ""}, socket), do: {:noreply, socket}

  def handle_event("send_message", %{"body" => body}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.channel

    case Chat.create_message(%{user_id: user.id, channel_id: channel.id, body: String.trim(body)}) do
      {:ok, _message} ->
        Chat.upsert_draft(user.id, channel.id, "")
        notify_other_users(user.id, channel)
        {:noreply, assign(socket, draft_body: "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Kunne ikke sende melding.")}
    end
  end

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
    {:noreply, assign(socket, current_user: updated_user)}
  end

  # ── Create channel ────────────────────────────────────────────────────────

  def handle_event("toggle_create_channel", _params, socket) do
    {:noreply, assign(socket, show_create_channel: !socket.assigns.show_create_channel, new_channel_slug: "")}
  end

  def handle_event("update_channel_slug", %{"slug" => slug}, socket) do
    {:noreply, assign(socket, new_channel_slug: String.downcase(slug))}
  end

  def handle_event("join_or_create_channel", %{"slug" => slug}, socket) do
    slug = String.downcase(String.trim(slug))

    if slug != "" do
      {:noreply,
       socket
       |> assign(show_create_channel: false)
       |> push_navigate(to: "/chat/#{slug}")}
    else
      {:noreply, socket}
    end
  end

  # ── PubSub handlers ───────────────────────────────────────────────────────

  def handle_info({:new_message, message}, socket) do
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

  def handle_info({:notification, _}, socket) do
    {:noreply, assign(socket, unread: socket.assigns.unread + 1)}
  end

  # ── Media upload ──────────────────────────────────────────────────────────

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("send_with_media", %{"body" => body}, socket) do
    user = socket.assigns.current_user
    channel = socket.assigns.channel

    uploaded_files =
      consume_uploaded_entries(socket, :media, fn %{path: tmp_path}, entry ->
        ext = Path.extname(entry.client_name)
        filename = "#{Ecto.UUID.generate()}#{ext}"
        dest = Chat.storage_path(filename)
        File.cp!(tmp_path, dest)
        {:ok, %{filename: filename, original_filename: entry.client_name, content_type: entry.client_type, file_size: entry.client_size, storage_path: dest}}
      end)

    if uploaded_files != [] || String.trim(body) != "" do
      case Chat.create_message(%{user_id: user.id, channel_id: channel.id, body: String.trim(body)}) do
        {:ok, message} ->
          Enum.each(uploaded_files, fn file -> Chat.attach_media(message.id, file) end)
          Chat.upsert_draft(user.id, channel.id, "")
          notify_other_users(user.id, channel)
          {:noreply, assign(socket, draft_body: "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Kunne ikke sende melding.")}
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
    <div
      id="pin-lock-watcher"
      phx-hook="PinLock"
      data-idle-minutes={@idle_minutes}
      class="hidden"
    />

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
          >Kanaler</p>
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
            + Opprett kanal
          </button>

          <%= if @show_create_channel do %>
            <form phx-submit="join_or_create_channel" class="space-y-1">
              <input
                type="text"
                name="slug"
                value={@new_channel_slug}
                phx-change="update_channel_slug"
                placeholder="kanalnavn"
                autofocus
                class="w-full px-2 py-1 text-sm rounded border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:outline-none focus:ring-1 focus:ring-blue-500"
              />
              <button type="submit" class="w-full py-1 text-xs bg-blue-600 hover:bg-blue-700 text-white rounded transition-colors">
                Gå til kanal
              </button>
            </form>
          <% end %>

          <.link navigate={~p"/bulletin"} class="block px-3 py-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors">
            📌 Oppslagstavle
          </.link>
        </div>

        <%!-- User + settings footer --%>
        <div class="p-3 border-t border-gray-200 dark:border-gray-700">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-gray-700 dark:text-gray-300 truncate">
              <%= @current_user.username %>
            </span>
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
          <span class="text-gray-500 dark:text-gray-400">Varsler:</span>
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
            <span class="text-gray-700 dark:text-gray-300">Aktiv</span>
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
            <span class="text-gray-700 dark:text-gray-300">Stille</span>
          </label>
          <span class="ml-auto text-gray-400 dark:text-gray-500 font-mono text-xs">#<%= @channel.slug %></span>
        </div>

        <%!-- Messages --%>
        <div
          id="messages"
          phx-hook="ScrollBottom"
          class="flex-1 overflow-y-auto px-4 py-4 space-y-3"
        >
          <%= for msg <- @messages do %>
            <div id={"msg-#{msg.id}"} class="group flex items-start gap-3">
              <div class="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900 flex items-center justify-center text-sm font-semibold text-blue-700 dark:text-blue-300">
                <%= String.first(msg.user.username) |> String.upcase() %>
              </div>
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
                      slett
                    </button>
                  <% end %>
                </div>
                <p class="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap break-words"><%= msg.body %></p>

                <%!-- Media attachments --%>
                <%= for attachment <- msg.media_attachments do %>
                  <div class="mt-2 max-w-sm">
                    <%= if Antisocial.Chat.MediaAttachment.image?(attachment) do %>
                      <img
                        src={"/media/#{attachment.storage_path}"}
                        alt={attachment.original_filename}
                        loading="lazy"
                        class="rounded-lg max-h-64 object-cover cursor-pointer hover:opacity-90"
                      />
                    <% else %>
                      <video
                        src={"/media/#{attachment.storage_path}"}
                        controls
                        preload="metadata"
                        class="rounded-lg max-w-full max-h-64"
                      />
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Typing indicator --%>
          <%= if @typing_users != [] do %>
            <div class="flex items-center gap-2 text-sm text-gray-400 dark:text-gray-500 italic">
              <div class="flex gap-0.5">
                <span class="w-1.5 h-1.5 rounded-full bg-gray-400 animate-bounce" style="animation-delay: 0ms" />
                <span class="w-1.5 h-1.5 rounded-full bg-gray-400 animate-bounce" style="animation-delay: 150ms" />
                <span class="w-1.5 h-1.5 rounded-full bg-gray-400 animate-bounce" style="animation-delay: 300ms" />
              </div>
              skriver...
            </div>
          <% end %>
        </div>

        <%!-- Composer --%>
        <div class="border-t border-gray-200 dark:border-gray-700 p-3">
          <form phx-submit="send_with_media" phx-change="validate_upload" class="space-y-2">
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

              <textarea
                id="composer"
                name="body"
                value={@draft_body}
                phx-hook="DraftAutosave"
                phx-keydown="send_message"
                phx-key="Enter"
                rows="1"
                placeholder="Skriv noe..."
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
    """
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end
  defp format_time(_), do: ""

  defp idle_minutes do
    Application.get_env(:antisocial, :idle_lock_minutes, @idle_minutes)
  end
end
