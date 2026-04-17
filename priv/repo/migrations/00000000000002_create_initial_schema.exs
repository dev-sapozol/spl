defmodule Spl.Repo.Migrations.CreateInitialSchema do
  use Ecto.Migration

  def up do
    # 1. Crear tipos ENUM para PostgreSQL
    execute("CREATE TYPE gender_enum AS ENUM ('MALE', 'FEMALE', 'OTHER')")
    execute("CREATE TYPE folder_type_enum AS ENUM ('SYSTEM', 'USER')")

    # 2. Crear tabla: user
    create table(:user, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :name, :string, size: 50
      add :role, :string, size: 20, default: "USER"
      add :password_hash, :string, size: 255
      add :email, :string, size: 50, null: false
      add :fathername, :string, size: 15
      add :mothername, :string, size: 15
      add :country, :string, size: 20
      add :birthdate, :date
      add :cellphone, :string, size: 15
      add :age, :integer
      add :gender, :gender_enum
      add :avatar_url, :string
      add :recovery_email, :string
      add :lenguage, :string, size: 2, default: "en"
      add :timezone, :string, size: 30

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user, [:email])
    create index(:user, [:avatar_url])
    create index(:user, [:recovery_email])

    # 3. Crear tabla: system_folders
    create table(:system_folders, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :name, :string, null: false
      add :default_page_size, :integer, default: 50

      timestamps(type: :utc_datetime)
    end

    create unique_index(:system_folders, [:name])

    # 4. Crear tabla: user_folders
    create table(:user_folders, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :user_id, references(:user, on_delete: :delete_all), null: false
      add :icon, :string, null: false
      add :name, :string, null: false
      add :page_size, :integer, default: 25

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_folders, [:user_id])

    # 5. Crear tabla: emails
    create table(:emails, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :user_id, references(:user, on_delete: :delete_all), null: false
      add :original_message_id, :string
      add :sender_email, :string
      add :sender_name, :string
      add :to_addresses, :map
      add :cc_addresses, :map
      add :subject, :string, size: 512
      add :preview, :string, size: 512
      add :is_read, :boolean, default: false
      add :has_attachment, :boolean, default: false
      add :importance, :integer, default: 0
      add :in_reply_to, :string, size: 255
      add :thread_id, :string, size: 255
      add :references, :map
      add :body_size_bytes, :integer
      add :attachments_size_bytes, :integer
      add :body_raw_storage_key, :string, size: 512
      add :body_storage_key, :string, size: 512
      add :folder_type, :folder_type_enum, null: false, default: "SYSTEM"
      add :folder_id, :bigint, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:emails, [:user_id])
    create index(:emails, [:sender_email, :to_addresses])
    create index(:emails, [:user_id, :folder_type, :folder_id], name: :idx_user_folder)
    create index(:emails, [:thread_id], name: :idx_thread)
    create index(:emails, [:original_message_id], name: :idx_message_id)

    # 6. Crear tabla: files
    create table(:files, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :email_id, references(:emails, on_delete: :delete_all), null: false
      add :user_id, references(:user, on_delete: :delete_all), null: false
      add :storage_provider, :string, null: false
      add :storage_key, :string, null: false
      add :original_filename, :string
      add :content_type, :string
      add :size, :integer
      add :checksum, :string
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create index(:files, [:email_id])
    create index(:files, [:user_id])
    create unique_index(:files, [:storage_provider, :storage_key])

    # 7. Seed system folders
    execute("""
      INSERT INTO system_folders (name, default_page_size, inserted_at, updated_at)
      VALUES
        ('Inbox', 50, now(), now()),
        ('Sent', 50, now(), now()),
        ('Drafts', 50, now(), now()),
        ('Trash', 50, now(), now()),
        ('Spam', 50, now(), now()),
        ('Archive', 50, now(), now()),
        ('Templates', 50, now(), now()),
        ('System', 50, now(), now())
      ON CONFLICT (name) DO NOTHING;
    """)
  end

  def down do
    drop table(:files)
    drop table(:emails)
    drop table(:user_folders)
    drop table(:system_folders)
    drop table(:user)

    execute("DROP TYPE folder_type_enum")
    execute("DROP TYPE gender_enum")
  end
end
