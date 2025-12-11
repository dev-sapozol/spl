defmodule Spl.Repo.Migrations.UpdateEmails2 do
  use Ecto.Migration

  def up do
    alter table(:emails) do
      remove :from
    end
  end

  def down do
    alter table(:emails) do
      add :from, :string, null: false
    end
  end
end
