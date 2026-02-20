defmodule Spl.MailBox do
  import Ecto.{Changeset, Query}, warn: false
  require Logger

  alias Spl.{Repo, EmailStorage, EmailCache}
  alias Spl.MailBox.{Emails, UserFolders, SystemFolders}
  alias Spl.Account.User

  def data(), do: Dataloader.Ecto.new(Repo, query: &query/2)

  def query(queryable, _params) do
    queryable
  end

  def assign_folder_type(folder, type) when type in [:SYSTEM, :USER] do
    Map.put(folder, :folder_type, type)
  end

  # Normalizar folder_type (string → atom)
  def normalize_folder_type(type) when is_binary(type) do
    type
    |> String.to_atom()
  end

  def normalize_folder_type(type) when is_atom(type), do: type

  def get_email(id) do
    from(e in Emails, where: e.id == ^id)
    |> Repo.one()
  end

  def get_email_metadata(id, user_id) do
    from(e in Emails,
      where: e.id == ^id and e.user_id == ^user_id,
      select: %{
        id: e.id,
        subject: e.subject,
        preview: e.preview,
        sender_email: e.sender_email,
        sender_name: e.sender_name,
        inserted_at: e.inserted_at,
        is_read: e.is_read,
        folder_id: e.folder_id,
        folder_type: e.folder_type,
        has_attachment: e.has_attachment
      }
    )
    |> Repo.one()
  end

  def get_email_with_body(id, user_id) do
    Logger.debug("Fetching email with body URL", metadata: [email_id: id, user_id: user_id])

    case from(e in Emails,
           where: e.id == ^id and e.user_id == ^user_id
         )
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      email ->
        case EmailCache.get_body_url(id) do
          {:ok, cached_url} ->
            Logger.debug("Body URL from cache", metadata: [email_id: id])
            {:ok, Map.put(email, :body_url, cached_url)}

          :error ->
            case EmailStorage.get_body_html_url(email.body_storage_key) do
              {:ok, body_url} ->
                EmailCache.set_body_url(id, body_url, 300)
                Logger.debug("Body URL generated and cached", metadata: [email_id: id])
                {:ok, Map.put(email, :body_url, body_url)}

              {:error, reason} ->
                Logger.error("Failed to get body URL",
                  metadata: [email_id: id, reason: inspect(reason)]
                )

                {:error, :body_fetch_failed}
            end
        end
    end
  end

  def get_raw_email_url(id, user_id, expires_in \\ 300) do
    Logger.debug("Fetching raw email URL", metadata: [email_id: id, user_id: user_id])

    case EmailCache.get_raw_url(id) do
      {:ok, cached_url} ->
        Logger.debug("Raw URL from cache", metadata: [email_id: id])
        {:ok, cached_url}

      :error ->
        case from(e in Emails,
               where: e.id == ^id and e.user_id == ^user_id,
               select: e.body_raw_storage_key
             )
             |> Repo.one() do
          nil ->
            {:error, :not_found}

          raw_key when is_binary(raw_key) ->
            case EmailStorage.get_raw_email_url(raw_key, expires_in) do
              {:ok, url} ->
                EmailCache.set_raw_url(id, url, expires_in)
                {:ok, url}

              {:error, _} = err ->
                err
            end

          _ ->
            {:ok, nil}
        end
    end
  end

  def get_email_full(id, user_id) do
    Logger.debug("Fetching complete email", metadata: [email_id: id, user_id: user_id])

    case from(e in Emails,
           where: e.id == ^id and e.user_id == ^user_id
         )
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      email ->
        with {:ok, body_url} <- fetch_or_cache_body_url(id, email.body_storage_key) do
          result =
            email
            |> Map.put(:body_url, body_url)
            |> maybe_put_raw_url(id)

          cacheable = email_to_cache_map(result)

          Logger.debug("Complete email fetched", metadata: [email_id: id])
          {:ok, cacheable}
        else
          {:error, reason} ->
            Logger.error("Failed to get complete email",
              metadata: [email_id: id, reason: inspect(reason)]
            )

            {:error, reason}
        end
    end
  end

  defp email_to_cache_map(email) do
    %{
      id: email.id,
      user_id: email.user_id,
      folder_id: email.folder_id,
      folder_type: email.folder_type,
      subject: email.subject,
      preview: email.preview,
      sender_email: email.sender_email,
      sender_name: email.sender_name,
      to: email.to_addresses,
      cc: email.cc_addresses,
      importance: email.importance,
      is_read: email.is_read,
      has_attachment: email.has_attachment,
      body_size_bytes: email.body_size_bytes,
      attachments_size_bytes: email.attachments_size_bytes,
      original_message_id: email.original_message_id,
      thread_id: email.thread_id,
      in_reply_to: email.in_reply_to,
      references: email.references,
      inserted_at: email.inserted_at,
      updated_at: email.updated_at,
      deleted_at: email.deleted_at,
      body_url: Map.get(email, :body_url),
      raw_url: Map.get(email, :raw_url)
    }
  end

  defp maybe_put_raw_url(email, email_id) do
    case email.body_raw_storage_key do
      nil ->
        email

      raw_key ->
        case fetch_or_cache_raw_url(email_id, raw_key) do
          {:ok, url} -> Map.put(email, :raw_url, url)
          _ -> email
        end
    end
  end

  defp fetch_or_cache_body_url(_email_id, nil), do: {:ok, nil}

  defp fetch_or_cache_body_url(email_id, storage_key) do
    case EmailCache.get_body_url(email_id) do
      {:ok, url} ->
        {:ok, url}

      :error ->
        case EmailStorage.get_body_html_url(storage_key) do
          {:ok, url} ->
            EmailCache.set_body_url(email_id, url, 300)
            {:ok, url}

          {:error, _} = err ->
            err
        end
    end
  end

  defp fetch_or_cache_raw_url(email_id, storage_key) do
    case EmailCache.get_raw_url(email_id) do
      {:ok, url} ->
        {:ok, url}

      :error ->
        case EmailStorage.get_raw_email_url(storage_key) do
          {:ok, url} ->
            EmailCache.set_raw_url(email_id, url, 300)
            {:ok, url}

          {:error, _} ->
            {:ok, nil}
        end
    end
  end

  def list_emails(args) do
    user_id = Map.get(args[:filter] || %{}, :user_id)
    folder_id = Map.get(args[:filter] || %{}, :folder_id)

    if user_id && folder_id do
      case EmailCache.get_inbox(user_id, folder_id) do
        {:ok, cached_emails} ->
          cached_emails

        :error ->
          emails =
            args
            |> email_query()
            |> order_by([e], desc: e.inserted_at)
            |> select_email_list_fields()
            |> Repo.all()

          # Cache with 60 second TTL
          EmailCache.set_inbox(user_id, folder_id, emails, 60)
          emails
      end
    else
      # No folder context, query directly
      args
      |> email_query()
      |> select_email_list_fields()
      |> Repo.all()
    end
  end

  def email_query(args) do
    base =
      Enum.reduce(args, Emails, fn
        {:filter, filter}, query -> email_filter(query, filter)
        {:limit, limit}, query -> from(e in query, limit: ^limit)
        {:offset, offset}, query -> from(e in query, offset: ^offset)
        _, query -> query
      end)

    base
  end

  def email_filter(query, filter) do
    Enum.reduce(filter, query, fn
      {:user_id, user_id}, query ->
        from(e in query, where: e.user_id == ^user_id)

      {:is_read, is_read}, query ->
        from(e in query, where: e.is_read == ^is_read)

      {:importance, importance}, query ->
        from(e in query, where: e.importance == ^importance)

      {:has_attachment, has_attachment}, query ->
        from(e in query, where: e.has_attachment == ^has_attachment)

      {:folder_id, folder_id}, query ->
        from(e in query, where: e.folder_id == ^folder_id)

      {:folder_type, folder_type}, query ->
        from(e in query, where: e.folder_type == ^folder_type)

      {:deleted_at, deleted_at}, query ->
        from(e in query, where: e.deleted_at == ^deleted_at)

      _, query ->
        query
    end)
  end

  defp select_email_list_fields(query) do
    from(e in query,
      select: %{
        id: e.id,
        subject: e.subject,
        preview: e.preview,
        sender_email: e.sender_email,
        sender_name: e.sender_name,
        inserted_at: e.inserted_at,
        is_read: e.is_read,
        has_attachment: e.has_attachment,
        importance: e.importance,
        folder_id: e.folder_id,
        folder_type: e.folder_type
      }
    )
  end

  @spec create_email(map()) ::
          {:ok, Emails.t()}
          | {:error, Ecto.Changeset.t()}
  def create_email(attrs \\ %{}) do
    %Emails{}
    |> Emails.changeset(attrs)
    |> Repo.insert()
  end

  def delete_email(%Emails{} = email) do
    result =
      email
      |> Emails.changeset(%{
        folder_type: :SYSTEM,
        folder_id: 4
      })
      |> Repo.update()

    case result do
      {:ok, deleted_email} ->
        EmailCache.invalidate_email_all(deleted_email.id)
        EmailCache.invalidate_inbox(deleted_email.user_id, deleted_email.folder_id)
        {:ok, deleted_email}

      {:error, _} = err ->
        err
    end
  end

  def preload_mailbox(user, limit \\ 50) do
    user_id = user.id
    {system_folders, user_folders} = load_folders(user_id)

    all_folders = system_folders ++ user_folders

    counts_by_folder = get_all_folder_counts(user_id)

    emails_by_folder =
      get_emails_for_all_folders(user_id, all_folders, limit)

    %{
      system_folders: enrich_folders_with_counts(system_folders, counts_by_folder),
      user_folders: enrich_folders_with_counts(user_folders, counts_by_folder),
      emails_by_folder: emails_by_folder
    }
  end

  defp load_folders(user_id) do
    [
      fn -> list_system_folders() |> Enum.map(&assign_folder_type(&1, :SYSTEM)) end,
      fn -> list_user_folders(user_id) |> Enum.map(&assign_folder_type(&1, :USER)) end
    ]
    |> Task.async_stream(& &1.(), max_concurrency: 2)
    |> Enum.map(fn {:ok, res} -> res end)
    |> List.to_tuple()
  end

  defp get_all_folder_counts(user_id) do
    from(e in Emails,
      where: e.user_id == ^user_id,
      group_by: [e.folder_id, e.folder_type],
      select: %{
        folder_id: e.folder_id,
        folder_type: e.folder_type,
        total: count(e.id),
        unread:
          fragment(
            "CAST(SUM(CASE WHEN ? = FALSE THEN 1 ELSE 0 END) AS SIGNED)",
            e.is_read
          )
      }
    )
    |> Repo.all()
    |> Map.new(fn c ->
      {{c.folder_id, c.folder_type}, %{total: c.total, unread: c.unread}}
    end)
  end

  defp enrich_folders_with_counts(folders, counts_map) do
    Enum.map(folders, fn folder ->
      key = {folder.id, normalize_folder_type(folder.folder_type)}
      counts = Map.get(counts_map, key, %{total: 0, unread: 0})
      Map.merge(folder, counts)
    end)
  end

  defp get_emails_for_all_folders(user_id, folders, limit) do
    my_user = Repo.get!(User, user_id)

    Enum.map(folders, fn folder ->
      folder_type = normalize_folder_type(folder.folder_type)
      special? = special_folder?(folder, folder_type)

      emails =
        fetch_emails_for_folder(user_id, folder, folder_type, limit)
        |> Enum.map(&decorate_email(&1, my_user, special?))

      %{
        folder_id: folder.id,
        folder_type: folder_type,
        emails: emails
      }
    end)
  end

  defp fetch_emails_for_folder(user_id, folder, folder_type, limit) do
    IO.inspect(limit, label: "EMAIL LIMIT")

    from(e in Emails,
      where:
        e.user_id == ^user_id and
          e.folder_id == ^folder.id and
          e.folder_type == ^folder_type,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp special_folder?(folder, :SYSTEM),
    do: folder.id in [2, 3, 7, 8]

  defp special_folder?(_, _), do: false

  defp decorate_email(email, my_user, true) do
    Map.merge(email, %{
      sender_name: my_user.name,
      sender_email: my_user.email
    })
  end

  defp decorate_email(email, _my_user, false) do
    sender =
      case email.user do
        %Ecto.Association.NotLoaded{} ->
          %{
            name: email.sender_name || "Unknown",
            email: email.sender_email || "unknown@example.com"
          }

        nil ->
          %{
            name: email.sender_name || "Unknown",
            email: email.sender_email || "unknown@example.com"
          }

        user ->
          %{name: user.name, email: user.email}
      end

    Map.merge(email, %{
      sender_name: sender.name,
      sender_email: sender.email
    })
  end

  def update_email_flags(%Emails{} = email, attrs) do
    result =
      email
      |> Emails.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_email} ->
        EmailCache.invalidate_email_meta(updated_email.id)
        EmailCache.invalidate_inbox(updated_email.user_id, updated_email.folder_id)
        {:ok, updated_email}

      {:error, _} = err ->
        err
    end
  end

  def mark_email_as_read(email_id, user_id) do
    case from(e in Emails, where: e.id == ^email_id and e.user_id == ^user_id)
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      email ->
        update_email_flags(email, %{is_read: true})
    end
  end

  def update_email_importance(email_id, user_id, importance) do
    case from(e in Emails, where: e.id == ^email_id and e.user_id == ^user_id)
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      email ->
        update_email_flags(email, %{importance: importance})
    end
  end

  # === TABLE SYSTEM FOLDERS ===

  def list_system_folders do
    Repo.all(SystemFolders)
  end

  def get_system_folder(id) do
    Repo.get(SystemFolders, id)
  end

  def create_system_folder(attrs \\ %{}) do
    %SystemFolders{}
    |> SystemFolders.changeset(attrs)
    |> Repo.insert()
  end

  def update_system_folder(attrs \\ %{}) do
    %SystemFolders{}
    |> SystemFolders.changeset(attrs)
    |> Repo.update()
  end

  def delete_system_folder(id) do
    Repo.get(SystemFolders, id)
    |> Repo.delete()
  end

  def list_user_folders(user_id) do
    from(uf in UserFolders, where: uf.user_id == ^user_id)
    |> Repo.all()
  end

  def get_user_folder(id), do: Repo.get(UserFolders, id)

  def create_user_folder(attrs \\ %{}) do
    %UserFolders{}
    |> UserFolders.changeset(attrs)
    |> Repo.insert()
  end

  def update_user_folder(attrs \\ %{}) do
    %UserFolders{}
    |> UserFolders.changeset(attrs)
    |> Repo.insert()
  end

  def delete_user_folder(id) do
    Repo.get(UserFolders, id)
    |> Repo.delete()
  end

  def invalidate_inbox_cache(user_id, folder_id) do
    EmailCache.invalidate_inbox(user_id, folder_id)
  end
end
