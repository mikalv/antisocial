defmodule Antisocial.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :recipient_id, references(:users, on_delete: :delete_all), null: false
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:recipient_id, :read_at])
  end
end
