defmodule Spl.SystemFoldersResolver do
  alias Spl.MailBox

  def list(_args, %{context: %{current_user: _current_user}}) do
    {:ok, MailBox.list_system_folders()}
  end

  def find(%{id: id}, %{context: %{current_user: _current_user}}) do
    case MailBox.get_system_folder(id) do
      nil -> {:error, "Folder not found"}
      folder -> {:ok, folder}
    end
  end

  def create(%{input: input}, _info) do
    MailBox.create_system_folder(input)
  end

  def update(%{input: input}, _info) do
    MailBox.update_system_folder(input)
  end

  def delete(%{id: id}, _info) do
    case MailBox.delete_system_folder(id) do
      {:ok, folder} -> {:ok, folder}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
