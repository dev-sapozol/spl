defmodule Spl.EmailCache do
  require Logger
  alias Spl.Cache

  ## Keys

  def inbox_key(user_id, folder_id) do
    "user:#{user_id}:inbox:#{folder_id}:emails"
  end

  def email_meta_key(email_id) do
    "email:#{email_id}:meta"
  end

  def body_url_key(email_id) do
    "email:#{email_id}:body_url"
  end

  def raw_url_key(email_id) do
    "email:#{email_id}:raw_url"
  end

  def get_inbox(user_id, folder_id) do
    key = inbox_key(user_id, folder_id)

    case Cache.get(key) do
      {:ok, emails} when is_list(emails) ->
        Logger.debug("Inbox cache HIT", metadata: [user_id: user_id, folder_id: folder_id])

        {:ok,
         Enum.map(emails, fn email ->
           Map.update!(email, :folder_type, &String.to_existing_atom/1)
         end)}

      _ ->
        Logger.debug("Inbox cache MISS", metadata: [user_id: user_id, folder_id: folder_id])
        :error
    end
  end

  def set_inbox(user_id, folder_id, emails, ttl \\ 60) do
    key = inbox_key(user_id, folder_id)

    emails =
      Enum.map(emails, fn email ->
        %{
          id: email.id,
          subject: email.subject,
          preview: email.preview,
          sender_email: email.sender_email,
          sender_name: email.sender_name,
          inserted_at: DateTime.to_iso8601(email.inserted_at),
          is_read: email.is_read,
          has_attachment: email.has_attachment,
          importance: email.importance,
          folder_id: email.folder_id,
          folder_type: Atom.to_string(email.folder_type)
        }
      end)

    Cache.set(key, emails, ttl)
  end

  def invalidate_inbox(user_id, folder_id) do
    Cache.del(inbox_key(user_id, folder_id))
  end

  def get_email_meta(email_id) do
    key = email_meta_key(email_id)

    case Cache.get(key) do
      {:ok, metadata} ->
        Logger.debug("Email meta cache HIT", metadata: [email_id: email_id])
        {:ok, normalize_from_cache(metadata)}

      :error ->
        Logger.debug("Email meta cache MISS", metadata: [email_id: email_id])
        :error
    end
  end

  def set_email_data(email_id, email, ttl \\ 600) do
    key = email_meta_key(email_id)
    Cache.set(key, normalize_for_cache(email), ttl)
  end

  def invalidate_email_meta(email_id) do
    Cache.del(email_meta_key(email_id))
  end

  def get_body_url(email_id) do
    key = body_url_key(email_id)

    case Cache.get(key) do
      {:ok, url} ->
        Logger.debug("Body URL cache HIT", metadata: [email_id: email_id])
        {:ok, url}

      :error ->
        Logger.debug("Body URL cache MISS", metadata: [email_id: email_id])
        :error
    end
  end

  def set_body_url(email_id, url, ttl \\ 300) do
    Cache.set(body_url_key(email_id), url, ttl)
  end

  def get_raw_url(email_id) do
    key = raw_url_key(email_id)

    case Cache.get(key) do
      {:ok, url} ->
        Logger.debug("Raw URL cache HIT", metadata: [email_id: email_id])
        {:ok, url}

      :error ->
        Logger.debug("Raw URL cache MISS", metadata: [email_id: email_id])
        :error
    end
  end

  def set_raw_url(email_id, url, ttl \\ 300) do
    Cache.set(raw_url_key(email_id), url, ttl)
  end

  def invalidate_email_all(email_id) do
    Cache.del_many([
      email_meta_key(email_id),
      body_url_key(email_id),
      raw_url_key(email_id)
    ])
  end

  def invalidate_all_inboxes(user_id, folder_ids) when is_list(folder_ids) do
    keys = Enum.map(folder_ids, &inbox_key(user_id, &1))
    Cache.del_many(keys)
  end

  defp normalize_for_cache(email) do
    email =
      if is_struct(email) do
        email
        |> Map.from_struct()
        |> Map.drop([:__meta__])
      else
        email
      end

    email
    |> Map.update(:folder_type, nil, &Atom.to_string/1)
    |> Map.update(:inserted_at, nil, &dt_to_iso/1)
    |> Map.update(:updated_at, nil, &dt_to_iso/1)
    |> Map.update(:deleted_at, nil, fn
      nil -> nil
      v -> dt_to_iso(v)
    end)
  end

  defp normalize_from_cache(email) do
    email
    |> Map.update(:folder_type, nil, fn
      v when is_binary(v) -> String.to_existing_atom(v)
      v -> v
    end)
  end

  defp dt_to_iso(%NaiveDateTime{} = dt),
    do: NaiveDateTime.to_iso8601(dt)

  defp dt_to_iso(%DateTime{} = dt),
    do: DateTime.to_iso8601(dt)

  defp dt_to_iso(v),
    do: v
end
