defmodule Spl.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def up do
    create table(:emails, primary_key: true) do
      add :user_id, references(:user, on_delete: :delete_all)
      add :original_message_id, :string
      add :from, :string, null: false
      add :to, :text
      add :cc, :text
      add :subject, :text
      add :preview, :text
      add :inbox_type, :integer
      add :is_read, :boolean, default: false
      add :has_attachment, :boolean, default: false
      add :importance, :integer
      add :in_reply_to, :text
      add :references, :text
      add :text_body, :text
      add :html_body, :text
      add :s3_url, :text
      add :thread_id, :string
      add :folder, :integer
      add :deleted_at, :utc_datetime

      timestamps()
    end

    execute "ALTER TABLE emails MODIFY in_reply_to LONGTEXT NULL"
    execute "ALTER TABLE emails MODIFY `references` LONGTEXT NULL"
    execute "ALTER TABLE emails MODIFY text_body LONGTEXT NOT NULL"
    execute "ALTER TABLE emails MODIFY html_body LONGTEXT NULL"
  end

  def down do
    drop table(:emails)
  end
end
