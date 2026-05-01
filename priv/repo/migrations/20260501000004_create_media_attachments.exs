defmodule Antisocial.Repo.Migrations.CreateMediaAttachments do
  use Ecto.Migration

  def change do
    create table(:media_attachments) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :original_filename, :string, null: false
      add :content_type, :string, null: false
      add :file_size, :bigint, null: false
      add :storage_path, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:media_attachments, [:message_id])
  end
end
