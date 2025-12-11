defmodule Spl.Repo.Migrations.CreateUserFolders do
  use Ecto.Migration

  def up do
    create table(:user_folders, primary_key: true) do
      add :user_id, references(:user, on_delete: :delete_all), null: false
      add :icon, :string, null: false
      add :name, :string, null: false
      add :page_size, :integer, default: 25
      timestamps()
    end

    create unique_index(:user_folders, [:user_id])
  end

  def down do
    drop table(:user_folders)
  end
end
