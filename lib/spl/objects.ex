defmodule Spl.Objects do
  import Ecto.{Changeset, Query}, warn: false

  alias Spl.Repo
  alias Spl.Objects.{Files}

  def data(), do: Dataloader.Ecto.new(Repo, query: &query/2)

  def query(queryable, _params) do
    queryable
  end

  def get_file(id), do: Repo.get(Files, id)

  def list_email_files(args) do
    args
    |> email_files_query
    |> Repo.all()
  end

  def email_files_query(args) do
    Enum.reduce(args, Files, fn
      {:filter, filter}, query -> query.email_files_filter(filter)
    end)
  end

  def email_files_filter(query, filter) do
    Enum.reduce(filter, query, fn
      {:email_id, email_id}, query ->
        from(e in query, where: e.email_id == ^email_id)
    end)
  end

  def create_file(attrs) do
    %Files{}
    |> Files.changeset(attrs)
    |> Repo.insert()
  end

  def soft_delete_file(%Files{} = file) do
    file
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
    |> Repo.update()
  end
end
