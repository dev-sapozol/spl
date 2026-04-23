defmodule Spl.Repo.Migrations.UpdateUser02 do
  use Ecto.Migration

  def up do
    alter table(:user) do
      add :ai_messages_used, :integer, default: 0, null: false
    end
  end
end
