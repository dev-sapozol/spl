defmodule Spl.MailBox.UserFolders do
  use Ecto.Schema
  import Ecto.Changeset
  alias Spl.Account.User

  schema "user_folders" do
    field :name, :string
    field :page_size, :integer, default: 25
    belongs_to :user, User

    timestamps()
  end

  def changeset(user_folders, attrs) do
    user_folders
    |> cast(attrs, [:name, :page_size])
    |> validate_required([:name])
  end
end
