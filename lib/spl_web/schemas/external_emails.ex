defmodule SplWeb.Schema.ExternalEmails do
  use Absinthe.Schema.Notation
  alias SplWeb.Schema.Middleware

  object :external_emails do
    field :id, non_null(:id)
    field :email, non_null(:string)
    field :status, non_null(:string)
    field :user_id, non_null(:id)
    field :inserted_at, non_null(:string)
    field :updated_at, non_null(:string)
  end

  object :get_external_email do
    field :id, non_null(:id)
    field :email, non_null(:string)
  end

  object :verification_status do
    field :status, non_null(:string)
    field :message, :string
  end

  object :external_emails_queries do
    field :list_external_emails, list_of(:get_external_email) do
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.ExternalEmailsResolver.list/2)
    end
  end

  object :external_emails_mutations do
    field :verify_external_email, :verification_status do
      arg(:email, non_null(:string))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.ExternalEmailsResolver.verify/2)
    end

    field :check_external_email, :verification_status do
      arg(:email, non_null(:string))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.ExternalEmailsResolver.check/2)
    end
  end
end
