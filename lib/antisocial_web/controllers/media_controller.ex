defmodule AntisocialWeb.MediaController do
  use AntisocialWeb, :controller

  def show(conn, %{"path" => path}) do
    # Sanitize path — prevent directory traversal
    safe_path = path |> Enum.join("/") |> Path.expand("/") |> String.trim_leading("/")
    full_path = Path.join(Antisocial.Chat.upload_dir(), safe_path)

    if File.exists?(full_path) && String.starts_with?(Path.expand(full_path), Path.expand(Antisocial.Chat.upload_dir())) do
      send_file(conn, 200, full_path)
    else
      send_resp(conn, 404, "Not found")
    end
  end
end
