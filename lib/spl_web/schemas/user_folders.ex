defmodule SplWeb.Schema.UserFolders do
  use Absinthe.Schema.Notation
  alias SplWeb.Schema.Middleware

  object :user_folders do
    field :id, :id
    field :user_id, :id
    field :name, :string
    field :page_size, :integer
    field :inserted_at, :string
    field :updated_at, :string
  end

  input_object :input_user_folder do
    field :user_id, non_null(:id)
    field :name, :string
    field :page_size, :integer
  end

  input_object :input_update_user_folder do
    field :name, :string
    field :page_size, :integer
  end

  # === QUERIES ===
  object :user_folders_queries do

    field :list_user_folders, list_of(:user_folders) do
      arg :user_id, non_null(:id)
      middleware Middleware.Authenticate, :all
      resolve &Spl.UserFoldersResolver.list/2
    end

    field :find_user_folder, type: :user_folders do
      arg :id, non_null(:id)
      middleware Middleware.Authenticate, :all
      resolve &Spl.UserFoldersResolver.find/2
    end
  end

  # === MUTATIONS ===
  object :user_folders_mutations do

    field :create_user_folder, type: :user_folders do
      arg :input, non_null(:input_user_folder)
      middleware Middleware.Authenticate, :all
      resolve &Spl.UserFoldersResolver.create/2
    end

    field :update_user_folder, type: :user_folders do
      arg :id, non_null(:id)
      arg :input, non_null(:input_update_user_folder)
      middleware Middleware.Authenticate, :all
      resolve &Spl.UserFoldersResolver.update/2
    end

    field :delete_user_folder, type: :user_folders do
      arg :id, non_null(:id)
      middleware Middleware.Authenticate, :all
      resolve &Spl.UserFoldersResolver.delete/2
    end
  end
end
