defmodule Spl.Repo.Migrations.UpdateEmails6 do
  use Ecto.Migration

  def up do
    alter table(:emails) do
      remove :text_body
      remove :html_body
      remove :s3_url
      remove :inbox_type
      remove :to
      remove :cc
      remove :references
      add :to_addresses, :map
      add :cc_addresses, :map
      add :references, :map    # Ahora será una lista JSON de strings
      add :body_size_bytes, :integer
      add :attachments_size_bytes, :integer
      add :body_raw_storage_key, :string, size: 512 # El .eml original
      add :body_storage_key, :string, size: 512     # El JSON procesado
      modify :subject, :string, size: 512
      modify :preview, :string, size: 512
      modify :is_read, :boolean, default: false
      modify :has_attachment, :boolean, default: false
      modify :importance, :integer, default: 0
      modify :in_reply_to, :string, size: 255
      modify :thread_id, :string, size: 255
    end

    create index(:emails, [:user_id, :folder_type, :folder_id], name: :idx_user_folder)
    create index(:emails, [:thread_id], name: :idx_thread)
    create index(:emails, [:original_message_id], name: :idx_message_id)
  end

  def down do
    alter table(:emails) do
      remove :to_addresses
      remove :cc_addresses
      remove :body_size_bytes
      remove :attachments_size_bytes
      remove :body_raw_storage_key
      remove :body_storage_key

      add :to, :string
      add :cc, :string
      add :text_body, :text
      add :html_body, :text
      add :s3_url, :string
      add :inbox_type, :integer
    end

    drop_if_exists index(:emails, [:user_id, :folder_type, :folder_id], name: :idx_user_folder)
    drop_if_exists index(:emails, [:thread_id], name: :idx_thread)
    drop_if_exists index(:emails, [:original_message_id], name: :idx_message_id)
  end
end
