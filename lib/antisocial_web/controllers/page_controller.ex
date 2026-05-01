defmodule AntisocialWeb.PageController do
  use AntisocialWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/chat/generelt")
  end

  def hemmelig(conn, _params) do
    redirect(conn, to: ~p"/chat/hemmelig")
  end
end
