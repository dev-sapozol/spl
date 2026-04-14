defmodule Spl.EmailStorage do
  require Logger
  alias Spl.CloudflareR2

  def upload_raw_email(raw_eml_binary, user_id)
      when is_binary(raw_eml_binary) and is_integer(user_id) do
    Logger.debug("Uploading raw MIME to R2",
      metadata: [user_id: user_id, size: byte_size(raw_eml_binary)]
    )

    CloudflareR2.upload(
      raw_eml_binary,
      "user/#{user_id}/emails/raw",
      "eml",
      "message/rfc822"
    )
    |> case do
      {:ok, key} ->
        Logger.debug("Raw MIME uploaded successfully", metadata: [key: key])
        {:ok, key}

      {:error, reason} ->
        Logger.error("Failed to upload raw MIME",
          metadata: [user_id: user_id, reason: inspect(reason)]
        )

        {:error, :storage_upload_failed}
    end
  end

  def upload_html_body(html_body, user_id) when is_binary(html_body) and is_integer(user_id) do
    Logger.debug("Uploading HTML body to R2",
      metadata: [user_id: user_id, size: byte_size(html_body)]
    )

    body_bytes = byte_size(html_body)

    CloudflareR2.upload(
      html_body,
      "user/#{user_id}/emails/body",
      "html",
      "text/html; charset=utf-8"
    )
    |> case do
      {:ok, key} ->
        Logger.debug("HTML body uploaded successfully", metadata: [key: key, size: body_bytes])
        {:ok, key, body_bytes}

      {:error, reason} ->
        Logger.error("Failed to upload HTML body",
          metadata: [user_id: user_id, reason: inspect(reason)]
        )

        {:error, :storage_upload_failed}
    end
  end

  def get_body_html_url(nil), do: {:ok, nil}

  def get_body_html_url(body_storage_key, expires_in \\ 300) when is_binary(body_storage_key) do
    Logger.debug("Generating presigned URL for HTML body",
      metadata: [key: body_storage_key, expires: expires_in]
    )

    case CloudflareR2.presigned_get(body_storage_key, expires_in: expires_in) do
      {:ok, url} ->
        Logger.debug("Presigned URL generated", metadata: [key: body_storage_key])
        {:ok, url}

      {:error, reason} ->
        Logger.error("Failed to get presigned URL",
          metadata: [key: body_storage_key, reason: inspect(reason)]
        )

        {:error, :storage_access_failed}
    end
  end

  def get_raw_email_url(raw_storage_key, expires_in \\ 300) when is_binary(raw_storage_key) do
    Logger.debug("Generating presigned URL for raw MIME",
      metadata: [key: raw_storage_key, expires: expires_in]
    )

    case CloudflareR2.presigned_get(raw_storage_key, expires_in: expires_in) do
      {:ok, url} ->
        {:ok, url}

      {:error, reason} ->
        Logger.error("Failed to get presigned URL for raw MIME",
          metadata: [key: raw_storage_key, reason: inspect(reason)]
        )

        {:error, :storage_access_failed}
    end
  end

  def calculate_attachments_size(attachments) when is_list(attachments) do
    attachments
    |> Enum.reduce(0, fn attachment, acc ->
      size = Map.get(attachment, :size, 0)
      acc + size
    end)
  end

  def calculate_attachments_size(_), do: 0

  def delete_from_r2(storage_key) when is_binary(storage_key) do
    Logger.debug("Deleting from R2", metadata: [key: storage_key])

    case CloudflareR2.delete(storage_key) do
      :ok ->
        Logger.debug("Successfully deleted from R2", metadata: [key: storage_key])
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete from R2",
          metadata: [key: storage_key, reason: inspect(reason)]
        )

        {:error, :storage_delete_failed}
    end
  end
end
