defmodule Spl.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def up do
    create table(:files) do
      add :email_id, references(:emails, on_delete: :delete_all), null: false
      add :user_id, references(:user, on_delete: :delete_all), null: false

      add :storage_provider, :string, null: false
      add :storage_key, :string, null: false

      add :original_filename, :string
      add :content_type, :string
      add :size, :integer
      add :checksum, :string

      add :deleted_at, :utc_datetime_usec

      timestamps()
    end

    create index(:files, [:email_id])
    create index(:files, [:user_id])
    create unique_index(:files, [:storage_provider, :storage_key])
  end

  def down do
    drop index(:files, [:email_id])
    drop index(:files, [:user_id])
    drop index(:files, [:storage_provider, :storage_key])

    drop table(:files)
  end
end
