defmodule AntisocialWeb.InviteController do
  use AntisocialWeb, :controller

  alias Antisocial.Accounts
  alias AntisocialWeb.UserAuth

  def show(conn, %{"token" => token}) do
    case Accounts.consume_invite_token(token) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> put_session(:must_change_password, true)
        |> redirect(to: ~p"/chat/generelt")

      {:error, _} ->
        conn
        |> put_flash(:error, "Invitasjonslenken er ugyldig eller utløpt.")
        |> redirect(to: ~p"/login")
    end
  end
end
