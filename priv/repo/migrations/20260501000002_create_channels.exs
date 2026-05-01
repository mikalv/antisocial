defmodule Antisocial.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :pin_required, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:slug])
  end
end
