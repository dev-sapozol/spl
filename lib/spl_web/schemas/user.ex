defmodule SplWeb.Schema.User do
  use Absinthe.Schema.Notation
  alias SplWeb.Schema.Middleware

  # === TYPE ===
    object :user do
      field :id, :id
      field :role, :string
      field :password_hash, :string
      field :email, :string
      field :fathername, :string
      field :mothername, :string
      field :country, :string
      field :birthdate, :date
      field :cellphone, :string
      field :age, :integer
      field :gender, :string
      field :lenguage, :string
      field :timezone, :string
      field :avatar_url, :string
      field :inserted_at, :string
      field :updated_at, :string
    end

    input_object :user_input do
      field :password_hash, :string
      field :email, :string
      field :fathername, :string
      field :mothername, :string
      field :country, :string
      field :birthdate, :date
      field :cellphone, :string
      field :gender, :string
      field :lenguage, :string
      field :timezone, :string
    end

    input_object :get_basic_data_user do
      field :id, :id
      field :name, :string
      field :fathername, :string
      field :mothername, :string
      field :email, :string
      field :country, :string
      field :cellphone, :string
      field :timezone, :string
      field :role, :string
      field :lenguage, :string
    end

    # === QUERIES ===

    object :user_queries do
      field :get_basic_data_user, :user do
        middleware Middleware.Authenticate, :all
        resolve &Spl.UserResolver.get_basic_data_user/3
      end
    end

    # === MUTATIONS ===

    object :user_mutations do
      field :update_user, type: :user do
        arg :id, non_null(:id)
        arg :input, non_null(:user_input)
        middleware Middleware.Authenticate, :all
        resolve &Spl.UserResolver.update/2
      end

      field :delete_user, type: :user do
        arg :id, :id
        middleware Middleware.Authenticate, :all
        resolve &Spl.UserResolver.delete/2
      end
    end
end
