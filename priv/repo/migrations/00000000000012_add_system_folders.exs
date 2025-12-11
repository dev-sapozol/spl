defmodule Spl.Repo.Migrations.AddSystemFolders do
  use Ecto.Migration

  def up do
    execute """
      INSERT INTO system_folders (name, default_page_size, inserted_at, updated_at) VALUES
      ('Inbox', 50, now(), now()),
      ('Sent', 50, now(), now()),
      ('Drafts', 50, now(), now()),
      ('Trash', 50, now(), now()),
      ('Spam', 50, now(), now()),
      ('Archive', 50, now(), now()),
      ('Templates', 50, now(), now()),
      ('System', 50, now(), now());
    """
  end

  def down do
    execute """
    DELETE FROM system_folders
    WHERE name IN (
      'Inbox',
      'Sent',
      'Drafts',
      'Trash',
      'Spam',
      'Archive',
      'Templates',
      'System')
    """
  end
end
