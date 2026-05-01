defmodule AntisocialWeb.UserAuth do
  use AntisocialWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Antisocial.Accounts

  @max_age 30 * 24 * 60 * 60
  @remember_me_cookie "_antisocial_user"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> put_resp_cookie(@remember_me_cookie, user.id |> to_string(), @remember_me_options)
  end

  def log_out_user(conn) do
    delete_resp_cookie(conn, @remember_me_cookie)
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  def fetch_current_user(conn, _opts) do
    {user_id, conn} = ensure_user_token(conn)
    user = user_id && Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Du må logge inn.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: ~p"/chat/generelt")
      |> halt()
    else
      conn
    end
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/chat/generelt")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(session, socket)}
  end

  defp mount_current_user(session, socket) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_id = session["user_id"] do
        Accounts.get_user(user_id)
      end
    end)
  end

  defp ensure_user_token(conn) do
    if user_id = get_session(conn, :user_id) do
      {user_id, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if user_id = conn.cookies[@remember_me_cookie] do
        user_id_int = String.to_integer(user_id)
        conn = put_session(conn, :user_id, user_id_int)
        {user_id_int, conn}
      else
        {nil, conn}
      end
    end
  end

  defp renew_session(conn) do
    delete_csrf_token()
    conn |> configure_session(renew: true) |> clear_session()
  end
end
