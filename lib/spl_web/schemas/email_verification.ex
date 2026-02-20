defmodule SplWeb.Schema.EmailVerification do
  use Absinthe.Schema.Notation
  alias SplWeb.Schema.Middleware

  object :verification_status do
    field :status, non_null(:string)
    field :message, :string
  end

  object :email_verification_queries do
    field :check_email_verification, :verification_status do
      arg :email, non_null(:string)
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailVerificationResolver.check/2)
    end
  end

  object :email_verification_mutations do
    field :verify_email, :verification_status do
      arg :email, non_null(:string)
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailVerificationResolver.verify/2)
    end
  end
end
