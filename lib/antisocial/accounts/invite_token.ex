defmodule Antisocial.Accounts.InviteToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invite_tokens" do
    field :token, :string
    field :type, :string, default: "invite"
    field :device_code, :string
    field :used_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :user, Antisocial.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(invite_token, attrs) do
    invite_token
    |> cast(attrs, [:user_id, :token, :expires_at, :type, :device_code])
    |> validate_required([:user_id, :token, :expires_at])
    |> validate_inclusion(:type, ["invite", "login"])
    |> unique_constraint(:token)
  end

  def generate_device_code do
    <<a, b, c>> = :crypto.strong_rand_bytes(3)
    code = (a * 65536 + b * 256 + c) |> rem(1_000_000)
    String.pad_leading(to_string(code), 6, "0")
  end

  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def expires_at(days \\ 7) do
    DateTime.utc_now() |> DateTime.add(days * 86_400, :second) |> DateTime.truncate(:second)
  end

  def expires_at_minutes(minutes) do
    DateTime.utc_now() |> DateTime.add(minutes * 60, :second) |> DateTime.truncate(:second)
  end
end
