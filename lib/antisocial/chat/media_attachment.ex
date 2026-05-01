defmodule Antisocial.Chat.MediaAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "media_attachments" do
    field :filename, :string
    field :original_filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :storage_path, :string

    belongs_to :message, Antisocial.Chat.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:message_id, :filename, :original_filename, :content_type, :file_size, :storage_path])
    |> validate_required([:message_id, :filename, :original_filename, :content_type, :file_size, :storage_path])
  end

  def image?(attachment), do: String.starts_with?(attachment.content_type, "image/")
  def video?(attachment), do: String.starts_with?(attachment.content_type, "video/")
  def audio?(attachment), do: String.starts_with?(attachment.content_type, "audio/")
end
