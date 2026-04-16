defmodule Spl.Account do
  import Ecto.{Changeset, Query}, warn: false

  alias Spl.Auth.Guardian
  alias Spl.{Repo}
  alias Spl.Account.User

  require Logger

  def data(), do: Dataloader.Ecto.new(Repo, query: &query/2)

  def query(queryable, _params) do
    queryable
  end

  def validate_token(token) do
    Guardian.verify_and_load_resource(token)
  end

  def authenticate_user(email, password) do
    case Repo.get_by(User, email: email) do
      nil ->
        {:error, :invalid_credentials}

      user ->
        result = Bcrypt.verify_pass(password, user.password_hash)

        if result do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  def generate_access_token(user) do
    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{}, token_type: :access)

    token
  end

  def generate_refresh_token(user) do
    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{}, token_type: :refresh)

    token
  end

  def check_email(email) do
    case Repo.get_by(User, email: email) do
      nil -> {:ok, false}
      _ -> {:ok, true}
    end
  end

  def change_user_password(user, old_pw, new_pw) do
    if Bcrypt.verify_pass(old_pw, user.password_hash) do
      user
      |> User.registration_changeset(%{password: new_pw})
      |> Repo.update()
    else
      {:error, :invalid_password}
    end
  end

  def reset_user_password(user, new_pw) do
    user
    |> User.registration_changeset(%{password: new_pw})
    |> Repo.update()
  end

  def get_basic_user(id) do
    from(u in User,
      where: u.id == ^id,
      select: %{
        id: u.id,
        email: u.email,
        role: u.role,
        name: u.name,
        fathername: u.fathername,
        mothername: u.mothername,
        country: u.country,
        cellphone: u.cellphone,
        timezone: u.timezone,
        lenguage: u.lenguage
      }
    )
    |> Repo.one()
  end

  def get_user(id), do: Repo.get(User, id)

  def get_user_id_by_email(email) do
    from(u in User, where: u.email == ^email, select: u.id) |> Repo.one()
  end

  def get_user_by_email(email) do
    from(u in User, where: u.email == ^email) |> Repo.one()
  end

  def list_users(args) do
    args
    |> user_query
    |> Repo.all()
  end

  def user_query(args) do
    Enum.reduce(args, User, fn
      {:filter, filter}, query -> query |> user_filter(filter)
    end)
  end

  def user_filter(query, filter) do
    Enum.reduce(filter, query, fn
      {:id, id}, query ->
        from(u in query, where: u.id == ^id)

      {:email, email}, query ->
        from(u in query, where: u.email == ^email)

      {:country, country}, query ->
        from(u in query, where: u.country == ^country)

      {:lenguage, lenguage}, query ->
        from(u in query, where: u.lenguage == ^lenguage)

      {:gender, gender}, query ->
        from(u in query, where: u.gender == ^gender)

      {:timezone, timezone}, query ->
        from(u in query, where: u.timezone == ^timezone)
    end)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, input) do
    user
    |> User.changeset(input)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def build_display_name(%{name: name, fathername: father, mothername: mother, email: email}) do
    parts =
      [name, father, mother]
      |> Enum.reject(&is_nil_or_blank/1)

    display = Enum.join(parts, " ")

    "#{display} <#{email}>"
  end

  defp is_nil_or_blank(value) do
    value in [nil, ""] or (is_binary(value) and String.trim(value) == "")
  end
end
