defmodule Antisocial.Repo.Migrations.CreateDrafts do
  use Ecto.Migration

  def change do
    create table(:drafts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :body, :text, null: false, default: ""
      add :rich_body, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:drafts, [:user_id, :channel_id])
  end
end
