defmodule Antisocial.Repo.Migrations.CreateUserSessions do
  use Ecto.Migration

  def change do
    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :user_agent, :string
      add :ip_addr, :string
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:user_sessions, [:token])
    create index(:user_sessions, [:user_id])
  end
end
