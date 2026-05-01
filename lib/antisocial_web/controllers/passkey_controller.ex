defmodule AntisocialWeb.PasskeyController do
  use AntisocialWeb, :controller

  alias Antisocial.{Accounts, PasskeyChallenge}

  # ── Registration (authenticated user adding a passkey) ────────────────────

  def register_challenge(conn, _params) do
    user = conn.assigns.current_user
    origin = endpoint_origin()
    rp_id = endpoint_rp_id()

    challenge =
      Wax.new_registration_challenge(
        attestation: "none",
        origin: origin,
        rp_id: rp_id,
        trusted_attestation_types: [:none, :self],
        verify_trust_root: false
      )

    session_id = get_session(conn, :session_id) || :crypto.strong_rand_bytes(16) |> Base.encode16()
    conn = put_session(conn, :session_id, session_id)
    PasskeyChallenge.put({:register, session_id}, challenge)

    passkeys = Accounts.list_passkeys(user.id)
    exclude_credentials =
      Enum.map(passkeys, fn pk ->
        %{type: "public-key", id: Base.url_encode64(pk.credential_id, padding: false)}
      end)

    json(conn, %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{name: "antisocial", id: rp_id},
      user: %{
        id: Base.url_encode64(<<user.id::32>>, padding: false),
        name: user.username,
        displayName: user.display_name || user.username
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},
        %{type: "public-key", alg: -257}
      ],
      excludeCredentials: exclude_credentials,
      authenticatorSelection: %{
        userVerification: "preferred",
        residentKey: "preferred"
      },
      timeout: 60_000
    })
  end

  def register(conn, %{"id" => _id, "rawId" => raw_id_b64, "response" => response} = _params) do
    user = conn.assigns.current_user
    session_id = get_session(conn, :session_id)

    with {:ok, challenge} <- PasskeyChallenge.pop({:register, session_id}),
         {:ok, att_obj} <- b64decode(response["attestationObject"]),
         {:ok, cdj} <- b64decode(response["clientDataJSON"]),
         {:ok, raw_id} <- b64decode(raw_id_b64),
         {:ok, {auth_data, _att_result}} <- Wax.register(att_obj, cdj, challenge) do
      acd = auth_data.attested_credential_data
      cose_key = acd.credential_public_key
      sign_count = auth_data.sign_count
      aaguid = format_aaguid(acd.aaguid)
      label = "Passkey #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d")}"

      case Accounts.create_passkey(user, raw_id, cose_key, sign_count, aaguid, label) do
        {:ok, _passkey} ->
          json(conn, %{ok: true})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: format_errors(changeset)})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  # ── Authentication (unauthenticated user logging in) ──────────────────────

  def auth_challenge(conn, params) do
    username = params["username"]
    origin = endpoint_origin()
    rp_id = endpoint_rp_id()

    allow_credentials =
      if username do
        user = Accounts.get_user_by_username(username)
        if user do
          Accounts.list_passkeys(user.id)
          |> Enum.map(fn pk -> %{type: "public-key", id: pk.credential_id} end)
        else
          []
        end
      else
        []
      end

    challenge =
      Wax.new_authentication_challenge(
        allow_credentials: allow_credentials,
        origin: origin,
        rp_id: rp_id,
        user_presence: true,
        user_verification: "preferred"
      )

    session_id = get_session(conn, :session_id) || :crypto.strong_rand_bytes(16) |> Base.encode16()
    conn = put_session(conn, :session_id, session_id)
    PasskeyChallenge.put({:auth, session_id}, challenge)

    allow_for_client =
      Enum.map(allow_credentials, fn %{id: cred_id} ->
        %{type: "public-key", id: Base.url_encode64(cred_id, padding: false)}
      end)

    json(conn, %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      allowCredentials: allow_for_client,
      userVerification: "preferred",
      rpId: rp_id,
      timeout: 60_000
    })
  end

  def auth(conn, %{"rawId" => raw_id_b64, "response" => response}) do
    session_id = get_session(conn, :session_id)

    with {:ok, stored_challenge} <- PasskeyChallenge.pop({:auth, session_id}),
         {:ok, raw_id} <- b64decode(raw_id_b64),
         {:ok, auth_data_bin} <- b64decode(response["authenticatorData"]),
         {:ok, sig} <- b64decode(response["signature"]),
         {:ok, cdj} <- b64decode(response["clientDataJSON"]),
         passkey when not is_nil(passkey) <- Accounts.get_passkey_by_credential_id(raw_id),
         cose_key <- Accounts.decode_passkey_cose_key(passkey),
         challenge <- %{stored_challenge | allow_credentials: [{raw_id, cose_key}]},
         {:ok, auth_result} <- Wax.authenticate(raw_id, auth_data_bin, sig, cdj, challenge) do
      # Update sign count (replay protection)
      Accounts.update_passkey_sign_count(passkey, auth_result.sign_count)

      # Log user in via invite token redirect bridge
      user = Accounts.get_user!(passkey.user_id)

      case Accounts.create_login_token(user) do
        {:ok, token} ->
          json(conn, %{redirect: "/invite/#{token.token}"})

        _ ->
          conn |> put_status(:internal_server_error) |> json(%{error: "login failed"})
      end
    else
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "unknown credential"})

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: inspect(reason)})
    end
  end

  # ── Delete passkey ─────────────────────────────────────────────────────────

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    Accounts.delete_passkey(user.id, String.to_integer(id))
    json(conn, %{ok: true})
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp endpoint_origin do
    uri = AntisocialWeb.Endpoint.url() |> URI.parse()
    "#{uri.scheme}://#{uri.host}#{if uri.port not in [80, 443], do: ":#{uri.port}", else: ""}"
  end

  defp endpoint_rp_id do
    AntisocialWeb.Endpoint.url() |> URI.parse() |> Map.get(:host)
  end

  defp b64decode(s) when is_binary(s) do
    # Accept both standard and URL-safe base64, with or without padding
    padded = pad_base64(String.replace(s, ["-", "_"], fn
      "-" -> "+"
      "_" -> "/"
    end))
    case Base.decode64(padded) do
      {:ok, _} = ok -> ok
      :error -> Base.url_decode64(s, padding: false)
    end
  end

  defp pad_base64(s) do
    case rem(byte_size(s), 4) do
      0 -> s
      2 -> s <> "=="
      3 -> s <> "="
      _ -> s
    end
  end

  defp format_aaguid(<<a::32, b::16, c::16, d::16, e::48>>) do
    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
  defp format_aaguid(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> inspect()
  end
end
