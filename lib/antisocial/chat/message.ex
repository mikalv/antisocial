defmodule Antisocial.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :body, :string, default: ""
    field :rich_body, :map
    field :archived_at, :utc_datetime
    field :geo_lat, :float
    field :geo_lng, :float
    field :ttl_seconds, :integer
    field :ttl_channel_slug, :string
    field :first_read_at, :utc_datetime

    belongs_to :user, Antisocial.Accounts.User
    belongs_to :channel, Antisocial.Chat.Channel
    has_many :media_attachments, Antisocial.Chat.MediaAttachment

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:user_id, :channel_id, :body, :rich_body, :geo_lat, :geo_lng, :ttl_seconds, :ttl_channel_slug])
    |> validate_required([:user_id, :channel_id])
    |> validate_length(:body, max: 10_000)
  end

  def archive_changeset(message) do
    change(message, archived_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
