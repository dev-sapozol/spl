defmodule Spl.Repo.Migrations.UpdateUser4 do
  use Ecto.Migration

  def up do
    alter table(:user) do
      add :recovery_email, :string, null: true
    end

    create index(:user, [:recovery_email])
  end

  def down do
    drop index(:user, [:recovery_email])

    alter table(:user) do
      remove :recovery_email
    end
  end
end
