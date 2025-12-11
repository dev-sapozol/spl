defmodule Spl.Repo.Migrations.CreateSystemFolders do
  use Ecto.Migration

  def up do
    create table(:system_folders) do
      add :name, :string, null: false
      add :default_page_size, :integer, default: 50
      timestamps()
    end

    create unique_index(:system_folders, [:name])
  end

  def down do
    drop table(:system_folders)
  end
end
