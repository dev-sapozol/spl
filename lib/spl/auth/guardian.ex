defmodule Spl.Auth.Guardian do
  use Guardian, otp_app: :spl
  alias Spl.Account

  @impl true
  def subject_for_token(user, _claims) do
    sub = to_string(user.id)
    {:ok, sub}
  end

  @impl true
  def resource_from_claims(%{"sub" => id}) do
    case Account.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def verify_and_load_resource(token) do
    case decode_and_verify(token) do
      {:ok, claims} -> resource_from_claims(claims)
      {:error, reason} -> {:error, reason}
    end
  end
end
