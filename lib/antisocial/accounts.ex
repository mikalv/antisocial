defmodule Antisocial.Accounts do
  import Ecto.Query
  alias Antisocial.Repo
  alias Antisocial.Accounts.{User, InviteToken}

  @session_validity_days 30

  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)
  def get_user_by_username(username), do: Repo.get_by(User, username: username)

  def authenticate(username, password) do
    user = get_user_by_username(username)

    cond do
      user && User.valid_password?(user, password) -> {:ok, user}
      user -> Bcrypt.no_user_verify(); {:error, :invalid_credentials}
      true -> Bcrypt.no_user_verify(); {:error, :invalid_credentials}
    end
  end

  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def update_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  def set_pin(user, pin) do
    user
    |> User.pin_changeset(%{pin: pin})
    |> Repo.update()
  end

  def clear_pin(user) do
    user
    |> User.clear_pin_changeset()
    |> Repo.update()
  end

  def update_settings(user, attrs) do
    user
    |> User.settings_changeset(attrs)
    |> Repo.update()
  end

  def mark_onboarded(user) do
    user
    |> User.onboarded_changeset()
    |> Repo.update()
  end

  def create_invite_token(user) do
    token = InviteToken.generate_token()

    %InviteToken{}
    |> InviteToken.changeset(%{
      user_id: user.id,
      token: token,
      expires_at: InviteToken.expires_at()
    })
    |> Repo.insert()
  end

  def consume_invite_token(token) do
    now = DateTime.utc_now()

    invite =
      Repo.one(
        from t in InviteToken,
          where: t.token == ^token and is_nil(t.used_at) and t.expires_at > ^now,
          preload: [:user]
      )

    case invite do
      nil ->
        {:error, :invalid_token}

      invite ->
        invite
        |> Ecto.Changeset.change(used_at: DateTime.truncate(now, :second))
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, invite.user}
          err -> err
        end
    end
  end

  def session_validity_seconds, do: @session_validity_days * 86_400

  def unread_notification_count(user_id) do
    Repo.one(
      from n in Antisocial.Accounts.Notification,
        where: n.recipient_id == ^user_id and is_nil(n.read_at),
        select: count()
    )
  end

  def create_notification(recipient_id) do
    %Antisocial.Accounts.Notification{}
    |> Antisocial.Accounts.Notification.changeset(%{recipient_id: recipient_id})
    |> Repo.insert()
  end

  def mark_all_notifications_read(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update_all(
      from(n in Antisocial.Accounts.Notification,
        where: n.recipient_id == ^user_id and is_nil(n.read_at)
      ),
      set: [read_at: now]
    )
  end
end
