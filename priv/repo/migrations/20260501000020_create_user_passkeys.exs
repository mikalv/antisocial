defmodule Antisocial.Repo.Migrations.CreateUserPasskeys do
  use Ecto.Migration

  def change do
    create table(:user_passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :cose_key, :binary, null: false
      add :sign_count, :integer, default: 0, null: false
      add :aaguid, :string
      add :label, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_passkeys, [:credential_id])
    create index(:user_passkeys, [:user_id])
  end
end
