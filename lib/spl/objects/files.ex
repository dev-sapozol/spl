defmodule Spl.Objects.Files do
  use Ecto.Schema
  import Ecto.Changeset
  alias Spl.Account.User
  alias Spl.MailBox.Emails

  schema "files" do
    belongs_to :email, Emails
    belongs_to :user, User
    field :storage_provider, :string
    field :storage_key, :string
    field :original_filename, :string
    field :content_type, :string
    field :size, :integer
    field :checksum, :string
    field :deleted_at, :utc_datetime_usec

    timestamps()
  end

  @required ~w(
    storage_provider
    storage_key
    content_type
    size
    email_id
    user_id
  )a

  @optional ~w(
    original_filename
    checksum
    deleted_at
  )a

  def changeset(file, attrs) do
    file
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:size, greater_than: 0)
    |> unique_constraint([:storage_provider, :storage_key])
  end
end
