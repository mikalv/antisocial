defmodule Antisocial.Repo.Migrations.AddIdleMinutesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :idle_minutes, :integer, default: 10
    end
  end
end
