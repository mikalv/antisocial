defmodule AntisocialWeb.InviteController do
  use AntisocialWeb, :controller

  alias Antisocial.Accounts
  alias AntisocialWeb.UserAuth

  def show(conn, %{"token" => token}) do
    case Accounts.consume_invite_token(token) do
      {:ok, user, "login"} ->
        conn
        |> UserAuth.log_in_user(user)
        |> redirect(to: ~p"/chat/generelt")

      {:ok, user, _} ->
        conn
        |> UserAuth.log_in_user(user)
        |> put_session(:must_change_password, true)
        |> redirect(to: ~p"/onboarding")

      {:error, _} ->
        conn
        |> put_flash(:error, "This link is invalid or has expired.")
        |> redirect(to: ~p"/login")
    end
  end
end
