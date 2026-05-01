defmodule Antisocial.Chat.BulletinPost do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bulletin_posts" do
    field :body, :string
    field :pinned, :boolean, default: true
    field :archived_at, :utc_datetime

    belongs_to :user, Antisocial.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:user_id, :body, :pinned])
    |> validate_required([:user_id, :body])
    |> validate_length(:body, max: 5_000)
  end

  def archive_changeset(post) do
    change(post, archived_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
