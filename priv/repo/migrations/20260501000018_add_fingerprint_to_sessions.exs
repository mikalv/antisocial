defmodule Antisocial.Repo.Migrations.AddFingerprintToSessions do
  use Ecto.Migration

  def change do
    alter table(:user_sessions) do
      add :fingerprint, :map
    end
  end
end
