defmodule Antisocial.Chat.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :slug, :string
    field :name, :string
    field :pin_required, :boolean, default: false

    has_many :messages, Antisocial.Chat.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:slug, :name, :pin_required])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/, message: "only lowercase letters, numbers, - and _")
    |> validate_length(:slug, min: 1, max: 50)
    |> unique_constraint(:slug)
  end
end
