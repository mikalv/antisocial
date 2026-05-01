defmodule Antisocial.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :channel_id, references(:channels, on_delete: :restrict), null: false
      add :body, :text, null: false, default: ""
      add :rich_body, :map
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:channel_id])
    create index(:messages, [:user_id])
    create index(:messages, [:channel_id, :archived_at])
  end
end
