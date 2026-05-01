defmodule Antisocial.Accounts do
  import Ecto.Query
  alias Antisocial.Repo
  alias Antisocial.Accounts.{User, InviteToken, UserSession, Passkey}

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

  def update_avatar(user, path) do
    user
    |> Ecto.Changeset.change(avatar_path: path)
    |> Repo.update()
  end

  def create_invite_token(user) do
    token = InviteToken.generate_token()

    %InviteToken{}
    |> InviteToken.changeset(%{
      user_id: user.id,
      token: token,
      type: "invite",
      expires_at: InviteToken.expires_at()
    })
    |> Repo.insert()
  end

  def create_login_token(user) do
    token = InviteToken.generate_token()
    device_code = InviteToken.generate_device_code()

    %InviteToken{}
    |> InviteToken.changeset(%{
      user_id: user.id,
      token: token,
      device_code: device_code,
      type: "login",
      expires_at: InviteToken.expires_at_minutes(15)
    })
    |> Repo.insert()
  end

  @reuse_window_seconds 300

  def consume_device_code(username, code) do
    now = DateTime.utc_now()
    reuse_cutoff = DateTime.add(now, -@reuse_window_seconds, :second)

    result =
      Repo.one(
        from t in InviteToken,
          join: u in assoc(t, :user),
          where:
            t.device_code == ^code and t.type == "login" and
              t.expires_at > ^now and
              (is_nil(t.used_at) or t.used_at > ^reuse_cutoff) and
              u.username == ^username,
          preload: [:user]
      )

    case result do
      nil ->
        {:error, :invalid_code}

      %{used_at: nil} = invite ->
        invite
        |> Ecto.Changeset.change(used_at: DateTime.truncate(now, :second))
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, invite.user}
          err -> err
        end

      already_used ->
        {:ok, already_used.user}
    end
  end

  def consume_invite_token(token) do
    now = DateTime.utc_now()
    reuse_cutoff = DateTime.add(now, -@reuse_window_seconds, :second)

    invite =
      Repo.one(
        from t in InviteToken,
          where:
            t.token == ^token and t.expires_at > ^now and
              (is_nil(t.used_at) or t.used_at > ^reuse_cutoff),
          preload: [:user]
      )

    case invite do
      nil ->
        {:error, :invalid_token}

      %{used_at: nil} = invite ->
        invite
        |> Ecto.Changeset.change(used_at: DateTime.truncate(now, :second))
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, invite.user, invite.type || "invite"}
          err -> err
        end

      already_used ->
        {:ok, already_used.user, already_used.type || "invite"}
    end
  end

  def session_validity_seconds, do: @session_validity_days * 86_400

  # ── Sessions ──────────────────────────────────────────────────────────────

  def create_session(user, opts \\ []) do
    token = UserSession.generate_token()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %UserSession{}
    |> UserSession.changeset(%{
      user_id: user.id,
      token: token,
      user_agent: opts[:user_agent],
      ip_addr: opts[:ip_addr],
      last_seen_at: now
    })
    |> Repo.insert()
  end

  def get_user_by_session_token(token) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@session_validity_days * 86_400, :second)

    Repo.one(
      from s in UserSession,
        join: u in assoc(s, :user),
        where: s.token == ^token and s.inserted_at > ^cutoff,
        preload: [user: u]
    )
    |> case do
      nil -> nil
      session ->
        # Touch last_seen_at (best-effort, no error if it fails)
        Repo.update_all(
          from(s in UserSession, where: s.id == ^session.id),
          set: [last_seen_at: DateTime.truncate(now, :second)]
        )
        session.user
    end
  end

  def list_sessions(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@session_validity_days * 86_400, :second)
    Repo.all(
      from s in UserSession,
        where: s.user_id == ^user_id and s.inserted_at > ^cutoff,
        order_by: [desc: s.last_seen_at]
    )
  end

  def delete_session(token) do
    Repo.delete_all(from s in UserSession, where: s.token == ^token)
  end

  def delete_all_sessions(user_id) do
    Repo.delete_all(from s in UserSession, where: s.user_id == ^user_id)
  end

  def store_fingerprint(session_token, fingerprint) when is_binary(session_token) do
    Repo.update_all(
      from(s in UserSession, where: s.token == ^session_token),
      set: [fingerprint: fingerprint]
    )
  end

  # ── Passkeys ──────────────────────────────────────────────────────────────

  def list_passkeys(user_id) do
    Repo.all(from p in Passkey, where: p.user_id == ^user_id, order_by: [asc: p.inserted_at])
  end

  def get_passkey_by_credential_id(credential_id) when is_binary(credential_id) do
    Repo.get_by(Passkey, credential_id: credential_id)
  end

  def create_passkey(user, credential_id, cose_key_term, sign_count, aaguid, label) do
    %Passkey{}
    |> Passkey.changeset(%{
      user_id: user.id,
      credential_id: credential_id,
      cose_key: :erlang.term_to_binary(cose_key_term),
      sign_count: sign_count,
      aaguid: aaguid,
      label: label
    })
    |> Repo.insert()
  end

  def update_passkey_sign_count(passkey, sign_count) do
    passkey
    |> Passkey.update_sign_count_changeset(sign_count)
    |> Repo.update()
  end

  def delete_passkey(user_id, passkey_id) do
    Repo.delete_all(from p in Passkey, where: p.id == ^passkey_id and p.user_id == ^user_id)
  end

  def decode_passkey_cose_key(passkey) do
    :erlang.binary_to_term(passkey.cose_key, [:safe])
  end

  # ── Keystroke analysis ────────────────────────────────────────────────────

  def update_keystroke_profile(user, intervals) when is_list(intervals) and length(intervals) >= 3 do
    existing = user.keystroke_profile || %{}
    n_old = Map.get(existing, "n", 0)
    mean_old = Map.get(existing, "mean", 0.0)
    m2_old = Map.get(existing, "m2", 0.0)

    # Welford's online algorithm — compute running mean and variance
    {n, mean, m2} =
      Enum.reduce(intervals, {n_old, mean_old, m2_old}, fn x, {n, mean, m2} ->
        n1 = n + 1
        delta = x - mean
        mean1 = mean + delta / n1
        delta2 = x - mean1
        {n1, mean1, m2 + delta * delta2}
      end)

    variance = if n > 1, do: m2 / (n - 1), else: 0.0

    profile = %{"n" => n, "mean" => mean, "m2" => m2, "variance" => variance}
    user |> Ecto.Changeset.change(keystroke_profile: profile) |> Repo.update()
    {:ok, profile}
  end

  def update_keystroke_profile(_user, _intervals), do: :ok

  def keystroke_anomaly_score(user, intervals) when is_list(intervals) and length(intervals) >= 3 do
    profile = user.keystroke_profile
    if is_nil(profile) or Map.get(profile, "n", 0) < 20 do
      nil
    else
      mean = profile["mean"]
      variance = profile["variance"]
      std = :math.sqrt(max(variance, 1.0))

      sample_mean = Enum.sum(intervals) / length(intervals)
      z = abs(sample_mean - mean) / std
      z
    end
  end

  def keystroke_anomaly_score(_user, _), do: nil

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
