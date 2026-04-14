defmodule Spl.Repo.Migrations.UpdateUser2 do
  use Ecto.Migration

  def up do
    alter table(:user) do
      add :avatar_url, :string
    end

    create index(:user, [:avatar_url])
  end

  def down do
    drop index(:user, [:avatar_url])

    alter table(:user) do
      remove :avatar_url
    end
  end
end
