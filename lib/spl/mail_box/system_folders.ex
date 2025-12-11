defmodule Spl.MailBox.SystemFolders do
  use Ecto.Schema
  import Ecto.Changeset

  schema "system_folders" do
    field :name, :string
    field :default_page_size, :integer, default: 50

    timestamps()
  end

  def changeset(system_folders, attrs) do
  system_folders
  |> cast(attrs, [:name, :default_page_size])
  |> validate_required([:name])
  |> unique_constraint(:name)
  end
end
