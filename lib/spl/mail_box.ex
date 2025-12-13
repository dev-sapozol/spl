defmodule Spl.MailBox do
  import Ecto.{Changeset, Query}, warn: false

  alias Spl.Repo

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

  # === TABLE EMAILS ===
  def get_email(id), do: Repo.get(Emails, id)

  def list_emails(args) do
    args
    |> email_query
    |> Repo.all()
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

      {:to, to}, query ->
        from(e in query, where: e.to == ^to)

      {:deleted_at, deleted_at}, query ->
        from(e in query, where: e.deleted_at == ^deleted_at)

      _, query ->
        query
    end)
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
    Repo.delete(email)
  end

  def preload_mailbox(user_id, limit) do
    system_folders =
      list_system_folders()
      |> Enum.map(&assign_folder_type(&1, :SYSTEM))
      |> Enum.map(fn folder ->
        folder_type = normalize_folder_type(folder.folder_type)

        total = count_emails_in_folder(user_id, folder.id, folder_type)
        unread = count_unread_in_folder(user_id, folder.id, folder_type)

        Map.merge(folder, %{
          total: total,
          unread: unread
        })
      end)

    user_folders =
      list_user_folders(user_id)
      |> Enum.map(&assign_folder_type(&1, :USER))
      |> Enum.map(fn folder ->
        folder_type = normalize_folder_type(folder.folder_type)

        total = count_emails_in_folder(user_id, folder.id, folder_type)
        unread = count_unread_in_folder(user_id, folder.id, folder_type)

        Map.merge(folder, %{
          total: total,
          unread: unread
        })
      end)

    folders = system_folders ++ user_folders

    emails_by_folder =
      folders
      |> Enum.map(fn folder ->
        folder_type = normalize_folder_type(folder.folder_type)

        emails =
          if folder_type == :SYSTEM and folder.id in [2, 3, 7, 8] do
            list_emails(%{
              filter: %{
                user_id: user_id,
                folder_id: folder.id,
                folder_type: folder_type
              },
              limit: limit
            })
          else
            list_emails(%{
              filter: %{
                user_id: user_id,
                folder_id: folder.id,
                folder_type: folder_type
              },
              limit: limit
            })
            |> Enum.map(fn email ->
              sender_data =
                if folder_type == :SYSTEM and folder.id in [2, 3, 7, 8] do
                  my_user = Repo.get(User, user_id)
                  %{name: my_user.name, email: my_user.email}
                else
                  Repo.get(User, email.user_id)
                  |> case do
                    nil -> %{name: "Unknown", email: "unknown@example.com"}
                    user -> %{name: user.name, email: user.email}
                  end
                end

              Map.merge(email, %{
                sender_name: sender_data.name,
                sender_email: sender_data.email
              })
            end)
          end

        %{
          folder_id: folder.id,
          folder_type: folder_type,
          emails: emails
        }
      end)

    %{
      system_folders: system_folders,
      user_folders: user_folders,
      emails_by_folder: emails_by_folder
    }
  end

  def count_emails_in_folder(user_id, folder_id, folder_type) do
    Repo.aggregate(
      from(e in Emails,
        where:
          e.user_id == ^user_id and
            e.folder_id == ^folder_id and
            e.folder_type == ^folder_type
      ),
      :count
    )
  end

  def count_unread_in_folder(user_id, folder_id, folder_type) do
    Repo.aggregate(
      from(e in Emails,
        where:
          e.user_id == ^user_id and
            e.folder_id == ^folder_id and
            e.folder_type == ^folder_type and
            e.is_read == false
      ),
      :count
    )
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
    |> Repo.update()
  end

  def delete_user_folder(id) do
    Repo.get(UserFolders, id)
    |> Repo.delete()
  end
end
