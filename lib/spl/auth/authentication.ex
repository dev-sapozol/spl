defmodule Spl.Auth.Authentication do
  alias Spl.Auth.Guardian
  alias Spl.Account
  alias Spl.Repo

    def login(email, password) do
    case Repo.get_by(Account.User, email: email) do
      nil ->
        {:error, "Invalid credentials"}

      user ->
        if user.password == password do
          {:ok, token, _claims} = Guardian.encode_and_sign(user)
          {:ok, %{user: user, token: token}}
        else
          {:error, "Invalid credentials"}
        end
    end
  end
end
