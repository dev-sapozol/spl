defmodule Spl.UserResolver do
  alias Spl.Account

  def get_basic_data_user(_parent, _args, %{context: %{current_user: user}}) do
    case Account.get_basic_user(user.id) do
      nil -> {:error, "User not found"}
      user -> {:ok, user}
    end
  end

  def update(
        %{id: id, input: input},
        %{context: %{current_user: _current_user}}
      ) do
    Account.get_user(id)
    |> Account.update_user(input)
  end

  def delete(%{id: id}, _info) do
    case Account.delete_user(id) do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
