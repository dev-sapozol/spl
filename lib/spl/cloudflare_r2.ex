defmodule Spl.CloudflareR2 do
  alias ExAws.S3

  # 10MB
  @max_file_size 30 * 1024 * 1024
  # 7 days
  @max_expires_in 604_800

  defp r2_config do
    r2 = Application.fetch_env!(:spl, :r2)

    %{
      access_key_id: r2[:access_key_id],
      secret_access_key: r2[:secret_access_key],
      region: "auto",
      s3: %{
        scheme: "https://",
        host: "#{r2[:account_id]}.r2.cloudflarestorage.com"
      }
    }
  end

  defp bucket do
    Application.fetch_env!(:spl, :r2)[:bucket_name]
  end

  def build_key(prefix, extension) do
    "#{prefix}/#{UUID.uuid4()}.#{extension}"
  end

  # UPLOAD

  def upload(binary, prefix, extension, content_type) do
    with :ok <- validate_size(binary),
         key <- build_key(prefix, extension),
         {:ok, _} <- do_upload(binary, key, content_type) do
      {:ok, key}
    else
      {:error, :file_too_large} ->
        {:error, "El archivo excede el límite de 30 MB"}

      {:error, {:http_error, code, _body}} ->
        {:error, "Cloudflare R2 respondió #{code}"}

      {:error, reason} ->
        {:error, "Error inesperado: #{inspect(reason)}"}
    end
  end

  defp do_upload(binary, key, content_type) do
    result =
      S3.put_object(bucket(), key, binary,
        content_type: content_type,
        acl: :private
      )
      |> ExAws.request(r2_config())

    result
  end

  # DOWNLOAD (signed url)

  def presigned_get(key, expires_in \\ 300) do
    expires_in =
      expires_in
      |> normalize_expires_in()

    S3.presigned_url(
      ExAws.Config.new(:s3, r2_config()),
      :get,
      bucket(),
      key,
      expires_in: expires_in
    )
  end

  defp normalize_expires_in(expires_in)
       when is_integer(expires_in) and
              expires_in > 0 and
              expires_in <= @max_expires_in do
    expires_in
  end

  defp normalize_expires_in(_), do: 300

  # DELETE

  def delete(key) do
    S3.delete_object(bucket(), key)
    |> ExAws.request(r2_config())
  end

  defp validate_size(binary) do
    if byte_size(binary) > @max_file_size do
      {:error, :file_too_large}
    else
      :ok
    end
  end
end
