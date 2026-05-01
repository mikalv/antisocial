defmodule Antisocial.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string, null: false
      add :hashed_password, :string, null: false
      add :pin_hash, :string
      add :notification_mode, :string, null: false, default: "stealth"
      add :theme, :string, null: false, default: "system"
      add :onboarded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])
  end
end
