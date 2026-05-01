defmodule Antisocial.Accounts.UserSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_sessions" do
    field :token, :string
    field :user_agent, :string
    field :ip_addr, :string
    field :last_seen_at, :utc_datetime
    field :fingerprint, :map

    belongs_to :user, Antisocial.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :token, :user_agent, :ip_addr, :last_seen_at, :fingerprint])
    |> validate_required([:user_id, :token])
    |> unique_constraint(:token)
  end

  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
