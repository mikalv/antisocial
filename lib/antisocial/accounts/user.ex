defmodule Antisocial.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :display_name, :string
    field :hashed_password, :string
    field :password, :string, virtual: true
    field :pin_hash, :string
    field :pin, :string, virtual: true
    field :notification_mode, :string, default: "stealth"
    field :theme, :string, default: "system"
    field :tab_title, :string, default: "Notes"
    field :tab_icon, :string, default: "bubbles_chat"
    field :idle_minutes, :integer, default: 10
    field :contact_aliases, :map, default: %{}
    field :onboarded_at, :utc_datetime
    field :avatar_path, :string
    field :keystroke_profile, :map

    has_many :messages, Antisocial.Chat.Message
    has_many :passkeys, Antisocial.Accounts.Passkey
    has_many :drafts, Antisocial.Chat.Draft
    has_many :invite_tokens, Antisocial.Accounts.InviteToken
    has_many :user_sessions, Antisocial.Accounts.UserSession

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :display_name])
    |> validate_required([:username, :password])
    |> validate_length(:username, min: 2, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/)
    |> validate_length(:password, min: 8)
    |> unique_constraint(:username)
    |> hash_password()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8)
    |> hash_password()
  end

  def pin_changeset(user, attrs) do
    user
    |> cast(attrs, [:pin])
    |> validate_length(:pin, min: 4, max: 12)
    |> hash_pin()
  end

  def clear_pin_changeset(user) do
    change(user, pin_hash: nil)
  end

  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:notification_mode, :theme, :tab_title, :tab_icon, :idle_minutes])
    |> validate_inclusion(:notification_mode, ["active", "stealth"])
    |> validate_inclusion(:theme, ["light", "dark", "system"])
    |> validate_number(:idle_minutes, greater_than: 0, less_than_or_equal_to: 120)
  end

  def onboarded_changeset(user) do
    change(user, onboarded_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def contact_aliases_changeset(user, aliases) when is_map(aliases) do
    change(user, contact_aliases: aliases)
  end

  def display_name_for(viewer, target) do
    Map.get(viewer.contact_aliases || %{}, to_string(target.id), target.username)
  end

  def valid_password?(user, password) do
    Bcrypt.verify_pass(password, user.hashed_password)
  end

  def valid_pin?(user, pin) do
    user.pin_hash != nil && Bcrypt.verify_pass(pin, user.pin_hash)
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :hashed_password, Bcrypt.hash_pwd_salt(password))
    end
  end

  defp hash_pin(changeset) do
    case get_change(changeset, :pin) do
      nil -> changeset
      pin -> put_change(changeset, :pin_hash, Bcrypt.hash_pwd_salt(pin))
    end
  end
end
