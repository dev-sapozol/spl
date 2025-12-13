defmodule Spl.Repo.Migrations.UpdateEmails4 do
  use Ecto.Migration

  def up do
    alter table(:emails) do
      add :sender_email, :string
      add :sender_name, :string
    end

    index(:emails, [:sender_email, :to])
  end

  def down do
    drop index(:emails, [:sender_email, :to])

    alter table(:emails) do
      remove :sender_email
      remove :sender_name
    end
  end
end
