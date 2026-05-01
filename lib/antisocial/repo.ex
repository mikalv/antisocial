defmodule Antisocial.Repo do
  use Ecto.Repo,
    otp_app: :antisocial,
    adapter: Ecto.Adapters.Postgres
end
