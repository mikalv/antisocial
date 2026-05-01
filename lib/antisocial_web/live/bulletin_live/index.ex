defmodule AntisocialWeb.BulletinLive do
  use AntisocialWeb, :live_view

  alias Antisocial.{Repo, Chat.BulletinPost}
  import Ecto.Query

  def mount(_params, _session, socket) do
    posts =
      Repo.all(
        from p in BulletinPost,
          where: is_nil(p.archived_at),
          order_by: [desc: p.inserted_at],
          preload: [:user]
      )

    {:ok, assign(socket, posts: posts, body: "", error: nil)}
  end

  def handle_event("post", %{"body" => body}, socket) do
    user = socket.assigns.current_user

    case Repo.insert(BulletinPost.changeset(%BulletinPost{}, %{user_id: user.id, body: body})) do
      {:ok, post} ->
        post = Repo.preload(post, :user)
        {:noreply, assign(socket, posts: [post | socket.assigns.posts], body: "")}

      {:error, _} ->
        {:noreply, assign(socket, error: "Kunne ikke poste.")}
    end
  end

  def handle_event("archive_post", %{"id" => id}, socket) do
    post = Enum.find(socket.assigns.posts, &(&1.id == String.to_integer(id)))

    if post && post.user_id == socket.assigns.current_user.id do
      post |> BulletinPost.archive_changeset() |> Repo.update()
      posts = Enum.reject(socket.assigns.posts, &(&1.id == post.id))
      {:noreply, assign(socket, posts: posts)}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-2xl font-semibold text-gray-900 dark:text-white mb-6">📌 Oppslagstavle</h1>

      <form phx-submit="post" class="mb-8">
        <textarea
          name="body"
          value={@body}
          placeholder="Skriv noe å dele..."
          rows="3"
          class="w-full px-4 py-3 rounded-xl border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
        />
        <div class="flex justify-end mt-2">
          <button type="submit" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-medium transition-colors">
            Post
          </button>
        </div>
      </form>

      <div class="space-y-4">
        <%= for post <- @posts do %>
          <div class="group p-4 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
            <div class="flex items-center justify-between mb-2">
              <span class="text-sm font-semibold text-gray-900 dark:text-white"><%= post.user.username %></span>
              <div class="flex items-center gap-3">
                <span class="text-xs text-gray-400"><%= Calendar.strftime(post.inserted_at, "%d.%m %H:%M") %></span>
                <%= if post.user_id == @current_user.id do %>
                  <button
                    phx-click="archive_post"
                    phx-value-id={post.id}
                    class="opacity-0 group-hover:opacity-100 text-xs text-gray-400 hover:text-red-500 transition-all"
                  >fjern</button>
                <% end %>
              </div>
            </div>
            <p class="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap"><%= post.body %></p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
