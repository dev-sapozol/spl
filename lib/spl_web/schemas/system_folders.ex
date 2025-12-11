defmodule SplWeb.Schema.SystemFolders do
  use Absinthe.Schema.Notation
  alias SplWeb.Schema.Middleware

  object :system_folders do
    field :id, :id
    field :name, :string
    field :default_page_size, :integer
    field :inserted_at, :string
    field :updated_at, :string
  end

  input_object :input_system_folder do
    field :name, :string
    field :default_page_size, :integer
  end

  # === QUERIES ===
  object :system_folders_queries do

    field :list_system_folders, list_of(:system_folders) do
      middleware Middleware.Authenticate, :all
      resolve &Spl.SystemFoldersResolver.list/2
    end

    field :find_system_folder, type: :system_folders do
      arg :id, non_null(:id)
      middleware Middleware.Authenticate, :all
      resolve &Spl.SystemFoldersResolver.find/2
    end
  end

  object :system_folders_mutations do

    field :create_system_folder, type: :system_folders do
      arg :input, non_null(:input_system_folder)
      middleware Middleware.Authenticate, :all
      resolve &Spl.SystemFoldersResolver.create/2
    end

    field :update_system_folder, type: :system_folders do
      arg :id, non_null(:id)
      arg :input, non_null(:input_system_folder)
      middleware Middleware.Authenticate, :all
      resolve &Spl.SystemFoldersResolver.update/2
    end

    field :delete_system_folder, type: :system_folders do
      arg :id, non_null(:id)
      middleware Middleware.Authenticate, :all
      resolve &Spl.SystemFoldersResolver.delete/2
    end
  end
end
