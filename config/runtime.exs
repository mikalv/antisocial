import Config

if config_env() == :prod do
  config :antisocial, AntisocialWeb.Endpoint, server: true

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :antisocial, Antisocial.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "antisocial.rprxy.mdma.sh"
  port = String.to_integer(System.get_env("PORT") || "4481")

  config :antisocial, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :antisocial, AntisocialWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    check_origin: false,
    secret_key_base: secret_key_base
end
