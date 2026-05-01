defmodule AntisocialWeb.SessionController do
  use AntisocialWeb, :controller

  alias Antisocial.Accounts
  alias AntisocialWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error: nil, layout: false)
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case Accounts.authenticate(username, password) do
      {:ok, user} ->
        dest = if is_nil(user.onboarded_at), do: ~p"/onboarding", else: ~p"/chat/generelt"
        conn
        |> UserAuth.log_in_user(user)
        |> redirect(to: dest)

      {:error, _} ->
        render(conn, :new, error: "Wrong username or password.", layout: false)
    end
  end

  def device_login(conn, %{"username" => username, "code" => code}) do
    case Accounts.consume_device_code(String.trim(username), String.trim(code)) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> redirect(to: ~p"/chat/generelt")

      {:error, _} ->
        render(conn, :new, error: "Invalid or expired device code.", layout: false)
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
  end
end
