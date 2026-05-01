defmodule Antisocial.Repo.Migrations.CreateInviteTokens do
  use Ecto.Migration

  def change do
    create table(:invite_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :used_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invite_tokens, [:token])
    create index(:invite_tokens, [:user_id])
  end
end
