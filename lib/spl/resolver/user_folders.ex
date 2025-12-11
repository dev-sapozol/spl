defmodule Spl.UserFoldersResolver do
  alias Spl.MailBox

  def list(%{user_id: user_id}, %{context: %{current_user: _current_user}}) do
    {:ok, MailBox.list_user_folders(user_id)}
  end

  def find(%{id: id}, %{context: %{current_user: _current_user}}) do
    case MailBox.get_user_folder(id) do
      nil -> {:error, "Folder not found"}
      folder -> {:ok, folder}
    end
  end

  def create(%{input: input}, _info) do
    MailBox.create_user_folder(input)
  end

  def update(%{input: input}, _info) do
    MailBox.update_user_folder(input)
  end

  def delete(%{id: id}, _info) do
    case MailBox.delete_user_folder(id) do
      {:ok, folder} -> {:ok, folder}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
