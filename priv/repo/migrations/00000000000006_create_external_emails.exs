defmodule Spl.Repo.Migrations.CreateExternalEmails do
  use Ecto.Migration

  def up do
    create table(:external_emails) do
      add :email, :string, null: false
      add :status, :string, default: "PENDING"
      add :user_id, references(:user, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:external_emails, [:email])
    create index(:external_emails, [:user_id])
  end

  def down do
    drop table(:external_emails)
  end
end
