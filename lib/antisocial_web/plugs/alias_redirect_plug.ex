defmodule AntisocialWeb.AliasRedirectPlug do
  @moduledoc """
  Redirects alias hostnames to the canonical host.
  Configure alias hosts via the ALIAS_HOSTS env var (comma-separated).
  E.g. ALIAS_HOSTS=marielle.mdma.sh,chat.mdma.sh
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    canonical = canonical_host()
    alias_hosts = alias_hosts()

    if conn.host in alias_hosts and canonical do
      url = "https://#{canonical}#{conn.request_path}"
      url = if conn.query_string != "", do: "#{url}?#{conn.query_string}", else: url

      conn
      |> put_resp_header("location", url)
      |> send_resp(301, "")
      |> halt()
    else
      conn
    end
  end

  defp canonical_host do
    Application.get_env(:antisocial, :canonical_host) ||
      System.get_env("PHX_HOST")
  end

  defp alias_hosts do
    case System.get_env("ALIAS_HOSTS") do
      nil -> []
      hosts -> hosts |> String.split(",") |> Enum.map(&String.trim/1)
    end
  end
end
