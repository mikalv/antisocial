defmodule Antisocial.Repo.Migrations.AddKeystrokeProfileToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :keystroke_profile, :map
    end
  end
end
