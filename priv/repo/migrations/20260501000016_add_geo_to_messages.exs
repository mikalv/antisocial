defmodule Antisocial.Repo.Migrations.AddGeoToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :geo_lat, :float
      add :geo_lng, :float
    end
  end
end
