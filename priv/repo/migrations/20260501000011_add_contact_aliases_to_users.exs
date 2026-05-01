defmodule Antisocial.Repo.Migrations.AddContactAliasesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Per-user map of %{target_user_id_string => display_name}
      # e.g. %{"3" => "Tore"} makes user 3 appear as "Tore" to this user
      add :contact_aliases, :map, default: %{}
    end
  end
end
