defmodule Antisocial.Repo.Migrations.AddTtlToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :ttl_seconds, :integer
      add :ttl_channel_slug, :string
      add :first_read_at, :utc_datetime
    end
  end
end
