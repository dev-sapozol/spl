defmodule SplWeb.Schema.Files do
  use Absinthe.Schema.Notation
  alias SplWeb.Schema.Middleware

  object :files do
    field :id, non_null(:id)
    field :email_id, non_null(:id)
    field :user_id, non_null(:id)

    field :original_filename, :string
    field :content_type, non_null(:string)
    field :size, non_null(:integer)

    field :download_url, non_null(:string) do
      resolve(&Spl.FilesResolver.download_url/3)
    end

    field :inserted_at, :string
    field :updated_at, :string
  end

  input_object :upload do
    field :filename, non_null(:string)
    field :content_type, non_null(:string)
    field :path, non_null(:string)
  end

  object :files_queries do
    field :email_files, non_null(list_of(non_null(:files))) do
      arg(:email_id, non_null(:id))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.FilesResolver.email_files/2)
    end
  end

  object :files_mutations do
    field :upload_email_file, non_null(:files) do
      arg(:email_id, non_null(:id))
      arg(:file, non_null(:upload))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.FilesResolver.upload_email_file/2)
    end

    field :delete_file, non_null(:files) do
      arg(:id, non_null(:id))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.FilesResolver.delete/2)
    end
  end
end
