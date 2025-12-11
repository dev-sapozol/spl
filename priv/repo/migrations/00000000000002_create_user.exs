defmodule Spl.Repo.Migrations.CreateUser do
  use Ecto.Migration

  def up do
    create table(:user, primary_key: true) do
      add :name, :string, size: 50
      add :role, :string, size: 20, default: "USER"
      add :password_hash, :string, size: 255
      add :email, :string, size: 50
      add :fathername, :string, size: 15
      add :mothername, :string, size: 15
      add :country, :string, size: 20
      add :birthdate, :date
      add :cellphone, :string, size: 15
      add :age, :integer
      add :gender, :string
      add :lenguage, :string, size: 2, default: "en"
      add :timezone, :string, size: 30

      timestamps()
    end

    create unique_index(:user, [:email])

    execute "ALTER TABLE user ADD CONSTRAINT gender_check CHECK (gender IN ('MALE', 'FEMALE', 'OTHER'))"

  end

  def down do
    drop table(:user)
  end
end
