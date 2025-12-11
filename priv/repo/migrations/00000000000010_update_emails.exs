defmodule Spl.Repo.Migrations.UpdateEmails do
  use Ecto.Migration

  def up do
    alter table(:emails) do
      add :folder_type, :string, null: false
      add :folder_id, :integer, null: false
      remove :folder
    end

    execute """
    UPDATE emails
    SET folder_type = 'SYSTEM'
    WHERE folder_type IS NULL OR folder_type = '';
    """

    execute """
    ALTER TABLE emails
    MODIFY folder_type ENUM('SYSTEM', 'USER') NOT NULL DEFAULT 'SYSTEM';
    """

    create index(:emails, [:folder_type, :folder_id])
  end

  def down do
    alter table(:emails) do
      remove :folder_type
      remove :folder_id
      add :folder, :integer
    end
  end
end
