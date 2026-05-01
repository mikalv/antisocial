defmodule Antisocial.Accounts.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notifications" do
    field :read_at, :utc_datetime

    belongs_to :recipient, Antisocial.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:recipient_id])
    |> validate_required([:recipient_id])
  end

  def mark_read_changeset(notification) do
    change(notification, read_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
