defmodule Spl.Files do
  alias Spl.Objects
  alias Spl.CloudflareR2

  def list_email_files(args) do
    Objects.list_email_files(args)
  end

  def upload_email_file(%{
        binary: binary,
        filename: filename,
        content_type: content_type,
        email_id: email_id,
        user_id: user_id
      }) do
    extension = extract_extension(filename)

    with {:ok, key} <-
           CloudflareR2.upload(
             binary,
             "emails",
             extension,
             content_type
           ),
         {:ok, file} <-
           Objects.create_file(%{
             storage_provider: "r2",
             storage_key: key,
             original_filename: filename,
             content_type: content_type,
             size: byte_size(binary),
             email_id: email_id,
             user_id: user_id
           }) do
      {:ok, file}
    else
      {:error, :file_too_large} ->
        {:error, :file_too_large}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def download_url(file) do
    CloudflareR2.presigned_get(file.storage_key)
  end

  def delete_file(file) do
    with {:ok, _} <- CloudflareR2.delete(file.storage_key),
         {:ok, updated} <- Objects.soft_delete_file(file) do
      {:ok, updated}
    end
  end

  defp extract_extension(filename) do
    filename
    |> Path.extname()
    |> String.trim_leading(".")
  end
end
