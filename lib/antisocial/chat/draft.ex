defmodule Antisocial.Chat.Draft do
  use Ecto.Schema
  import Ecto.Changeset

  schema "drafts" do
    field :body, :string, default: ""
    field :rich_body, :map

    belongs_to :user, Antisocial.Accounts.User
    belongs_to :channel, Antisocial.Chat.Channel

    timestamps(type: :utc_datetime)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:user_id, :channel_id, :body, :rich_body])
    |> validate_required([:user_id, :channel_id])
  end
end
