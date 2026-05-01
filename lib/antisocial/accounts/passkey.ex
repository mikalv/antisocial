defmodule Antisocial.Accounts.Passkey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_passkeys" do
    field :credential_id, :binary
    field :cose_key, :binary
    field :sign_count, :integer, default: 0
    field :aaguid, :string
    field :label, :string

    belongs_to :user, Antisocial.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:user_id, :credential_id, :cose_key, :sign_count, :aaguid, :label])
    |> validate_required([:user_id, :credential_id, :cose_key])
    |> unique_constraint(:credential_id)
  end

  def update_sign_count_changeset(passkey, sign_count) do
    change(passkey, sign_count: sign_count)
  end
end
