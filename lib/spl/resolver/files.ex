defmodule Spl.FilesResolver do
  alias Spl.Files

  def email_files(args, %{context: %{current_user: user}}) do
    files =
      Files.list_email_files(args)
      |> Enum.filter(&(&1.user_id == user.id))

    {:ok, files}
  end

  def download_url(file, _args, _res) do
    {:ok, Files.download_url(file)}
  end

  def upload_email_file(args, %{context: %{current_user: user}}) do
    case args[:file] do
      %{path: path, filename: filename, content_type: content_type} ->
        Files.upload_email_file(%{
          binary: File.read!(path),
          filename: filename,
          content_type: content_type,
          email_id: args.email_id,
          user_id: user.id
        })

      nil ->
        {:error, "El archivo es nulo."}

      _ ->
        {:error, "Formato de archivo desconocido."}
    end
  end

  def delete(%{id: id}, %{context: %{current_user: _context_user}}) do
    case Files.delete_file(id) do
      {:ok, file} -> {:ok, file}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
