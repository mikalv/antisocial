defmodule Antisocial.Repo.Migrations.AddDisguiseToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :tab_title, :string, default: "Notes"
      add :tab_icon, :string, default: "default"
    end
  end
end
