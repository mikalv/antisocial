defmodule AntisocialWeb.UserAuth do
  use AntisocialWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Antisocial.Accounts

  @max_age 30 * 24 * 60 * 60
  @session_cookie "_antisocial_session"
  @cookie_options [sign: true, max_age: @max_age, same_site: "Lax", http_only: true]

  def log_in_user(conn, user) do
    user_agent = get_req_header(conn, "user-agent") |> List.first()
    ip_addr = conn.remote_ip |> :inet.ntoa() |> to_string()

    {:ok, session} = Accounts.create_session(user, user_agent: user_agent, ip_addr: ip_addr)

    conn
    |> renew_session()
    |> put_session(:session_token, session.token)
    |> put_resp_cookie(@session_cookie, session.token, @cookie_options)
  end

  def log_out_user(conn) do
    token = get_session(conn, :session_token) || conn.cookies[@session_cookie]
    if token, do: Accounts.delete_session(token)

    conn
    |> renew_session()
    |> delete_resp_cookie(@session_cookie)
    |> redirect(to: ~p"/login")
  end

  def fetch_current_user(conn, _opts) do
    {token, conn} = ensure_session_token(conn)
    user = token && Accounts.get_user_by_session_token(token)
    assign(conn, :current_user, user)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
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
      token = session["session_token"]
      token && Accounts.get_user_by_session_token(token)
    end)
  end

  defp ensure_session_token(conn) do
    if token = get_session(conn, :session_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@session_cookie])

      if token = conn.cookies[@session_cookie] do
        conn = put_session(conn, :session_token, token)
        {token, conn}
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
