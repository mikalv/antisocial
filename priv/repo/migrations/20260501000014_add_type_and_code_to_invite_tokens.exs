defmodule Antisocial.Repo.Migrations.AddTypeAndCodeToInviteTokens do
  use Ecto.Migration

  def change do
    alter table(:invite_tokens) do
      add :type, :string, default: "invite"
      add :device_code, :string
    end

    create index(:invite_tokens, [:device_code])
  end
end
