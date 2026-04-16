defmodule Spl.Account.User do
  use Ecto.Schema
  alias Spl.{Repo}
  import Ecto.{Changeset, Query}, warn: false

  schema "user" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :role, :string
    field :name, :string
    field :fathername, :string
    field :mothername, :string
    field :country, :string
    field :cellphone, :string
    field :timezone, :string
    field :lenguage, :string
    field :birthdate, :date
    field :age, :integer
    field :gender, :string
    field :avatar_url, :string
    field :recovery_email, :string

    timestamps()
  end

  # CHANGSET PARA UPDATE (el que te falta)
  @update_fields [
    :email,
    :role,
    :name,
    :fathername,
    :mothername,
    :country,
    :cellphone,
    :timezone,
    :lenguage,
    :birthdate,
    :age,
    :gender,
    :avatar_url
  ]

  def changeset(user, attrs) do
    user
    |> cast(attrs, [@update_fields, :recovery_email])
    |> validate_format(:recovery_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "invalid email format"
    )
    |> validate_required([:email, :name])
  end

  # CHANGSET DE REGISTRO
  @required_reg [
    :email,
    :password,
    :name,
    :fathername,
    :country,
    :cellphone,
    :timezone,
    :lenguage,
    :birthdate,
    :age,
    :gender
  ]

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, @required_reg ++ [:mothername])
    |> validate_required(@required_reg)
    |> validate_email_domain()
    |> validate_length(:password, min: 8)
    |> validate_email_username_unique()
    |> put_change(:role, "USER")
    |> unsafe_drop_role(attrs)
    |> put_password_hash()
  end

  defp unsafe_drop_role(changeset, _attrs) do
    delete_change(changeset, :role)
  end

  defp validate_email_domain(changeset) do
    validate_change(changeset, :email, fn :email, value ->
      if String.ends_with?(value, "@esanpol.xyz") do
        []
      else
        [email: :invalid]
      end
    end)
  end

  defp validate_email_username_unique(changeset) do
    case get_change(changeset, :email) do
      nil ->
        changeset

      email ->
        username =
          email
          |> String.split("@")
          |> List.first()

        query =
          from u in __MODULE__,
            where: like(fragment("LOWER(?)", u.email), ^"#{String.downcase(username)}@%")

        if Repo.exists?(query) do
          add_error(changeset, :email, "email_already_exists")
        else
          changeset
        end
    end
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end
end
