defmodule Antisocial.Chat do
  import Ecto.Query
  alias Antisocial.Repo
  alias Antisocial.Chat.{Channel, Message, Draft, MediaAttachment}

  # ── Channels ──────────────────────────────────────────────────────────────

  def get_channel_by_slug(slug), do: Repo.get_by(Channel, slug: slug)

  def get_or_create_channel(slug, opts \\ []) do
    case get_channel_by_slug(slug) do
      nil ->
        attrs = %{
          slug: slug,
          name: "##{slug}",
          pin_required: Keyword.get(opts, :pin_required, false)
        }

        %Channel{}
        |> Channel.changeset(attrs)
        |> Repo.insert()

      channel ->
        {:ok, channel}
    end
  end

  def list_public_channels do
    Repo.all(from c in Channel, where: not c.pin_required, order_by: c.inserted_at)
  end

  # ── Messages ──────────────────────────────────────────────────────────────

  def list_messages(channel_id, limit \\ 50) do
    Repo.all(
      from m in Message,
        where: m.channel_id == ^channel_id and is_nil(m.archived_at),
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        preload: [:user, :media_attachments]
    )
  end

  def list_archived_messages(channel_id) do
    Repo.all(
      from m in Message,
        where: m.channel_id == ^channel_id and not is_nil(m.archived_at),
        order_by: [desc: m.archived_at],
        preload: [:user, :media_attachments]
    )
  end

  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = Repo.preload(message, [:user, :media_attachments])
        broadcast_message(message)
        {:ok, message}

      err ->
        err
    end
  end

  def move_message(%Message{} = message, target_channel_id, _user_id) do
    old_channel_id = message.channel_id

    message
    |> Ecto.Changeset.change(channel_id: target_channel_id)
    |> Repo.update()
    |> case do
      {:ok, moved} ->
        # Remove from source channel view
        broadcast_archive(%{message | id: message.id, channel_id: old_channel_id})
        # Notify target channel
        moved = Repo.preload(moved, [:user, :media_attachments])
        broadcast_message(moved)
        {:ok, moved}

      err ->
        err
    end
  end

  def archive_message(%Message{} = message) do
    message
    |> Message.archive_changeset()
    |> Repo.update()
    |> case do
      {:ok, message} ->
        broadcast_archive(message)
        {:ok, message}

      err ->
        err
    end
  end

  defp broadcast_message(message) do
    Phoenix.PubSub.broadcast(
      Antisocial.PubSub,
      "channel:#{message.channel_id}",
      {:new_message, message}
    )
  end

  defp broadcast_archive(message) do
    Phoenix.PubSub.broadcast(
      Antisocial.PubSub,
      "channel:#{message.channel_id}",
      {:message_archived, message.id}
    )
  end

  def broadcast_typing(channel_id, user_id, typing?) do
    Phoenix.PubSub.broadcast(
      Antisocial.PubSub,
      "channel:#{channel_id}",
      {:typing, user_id, typing?}
    )
  end

  # ── Drafts ────────────────────────────────────────────────────────────────

  def get_draft(user_id, channel_id) do
    Repo.get_by(Draft, user_id: user_id, channel_id: channel_id)
  end

  def upsert_draft(user_id, channel_id, body) do
    case get_draft(user_id, channel_id) do
      nil ->
        %Draft{}
        |> Draft.changeset(%{user_id: user_id, channel_id: channel_id, body: body})
        |> Repo.insert()

      draft ->
        draft
        |> Draft.changeset(%{body: body})
        |> Repo.update()
    end
  end

  # ── Media ─────────────────────────────────────────────────────────────────

  def attach_media(message_id, attrs) do
    %MediaAttachment{}
    |> MediaAttachment.changeset(Map.put(attrs, :message_id, message_id))
    |> Repo.insert()
  end

  def upload_dir do
    Application.get_env(:antisocial, :upload_dir, "uploads")
  end

  def storage_rel_path(filename) do
    date = Date.utc_today()
    Path.join([
      to_string(date.year),
      String.pad_leading(to_string(date.month), 2, "0"),
      String.pad_leading(to_string(date.day), 2, "0"),
      filename
    ])
  end

  def storage_path(filename) do
    rel = storage_rel_path(filename)
    abs = Path.join(upload_dir(), rel)
    File.mkdir_p!(Path.dirname(abs))
    abs
  end

  # ── TTL ───────────────────────────────────────────────────────────────────

  def mark_first_read(%Message{ttl_seconds: nil}, _viewer_id), do: :ok
  def mark_first_read(%Message{first_read_at: fa}, _viewer_id) when not is_nil(fa), do: :ok
  def mark_first_read(%Message{user_id: uid}, viewer_id) when uid == viewer_id, do: :ok

  def mark_first_read(%Message{} = message, _viewer_id) do
    message
    |> Ecto.Changeset.change(first_read_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
    :ok
  end

  def list_expired_ttl_messages do
    now = DateTime.utc_now()

    Repo.all(
      from m in Message,
        where:
          not is_nil(m.ttl_seconds) and not is_nil(m.first_read_at) and is_nil(m.archived_at),
        preload: [:user, :media_attachments]
    )
    |> Enum.filter(fn m ->
      DateTime.diff(now, m.first_read_at, :second) >= m.ttl_seconds
    end)
  end
end
