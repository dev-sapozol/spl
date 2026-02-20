defmodule SplWeb.Schema do
  use Absinthe.Schema
  alias SplWeb.Schema.Middleware

  alias Spl.{
    Account,
    MailBox,
    Objects
  }

  import_types(Absinthe.Type.Custom)
  import_types(SplWeb.Schema.Scalars)
  import_types(__MODULE__.User)
  import_types(__MODULE__.Emails)
  import_types(__MODULE__.SystemFolders)
  import_types(__MODULE__.UserFolders)
  import_types(__MODULE__.EmailVerification)
  import_types(__MODULE__.Files)

  query do
    import_fields(:user_queries)
    import_fields(:email_queries)
    import_fields(:system_folders_queries)
    import_fields(:user_folders_queries)
    import_fields(:email_verification_queries)
    import_fields(:files_queries)
  end

  mutation do
    import_fields(:user_mutations)
    import_fields(:email_mutations)
    import_fields(:system_folders_mutations)
    import_fields(:user_folders_mutations)
    import_fields(:email_verification_mutations)
    import_fields(:files_mutations)
  end

  def dataloader() do
    Dataloader.new()
    |> Dataloader.add_source(Account, Account.data())
    |> Dataloader.add_source(MailBox, MailBox.data())
    |> Dataloader.add_source(Objects, Objects.data())
  end

  def context(ctx) do
    Map.put(ctx, :loader, dataloader())
  end

  def plugins do
    [Absinthe.Middleware.Dataloader | Absinthe.Plugin.defaults()]
  end

  def middleware(middleware, _field, %{identifier: :mutation}) do
    middleware ++ [Middleware.ChangesetErrors]
  end

  def middleware(middleware, _field, _object) do
    middleware
  end
end
