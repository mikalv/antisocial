defmodule Antisocial.Repo.Migrations.CreateBulletinPosts do
  use Ecto.Migration

  def change do
    create table(:bulletin_posts) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :body, :text, null: false
      add :pinned, :boolean, null: false, default: true
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:bulletin_posts, [:archived_at])
  end
end
