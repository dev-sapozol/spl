defmodule Spl.EmailVerificationResolver do
  alias Spl.Sender

  def verify(%{email: email}, _ctx) do
    case Sender.verify_email(email) do
      {:ok, status} ->
        {:ok,
         %{
           status: status
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def check(%{email: email}, _ctx) do
    case Sender.check_email_status(email) do
      {:ok, status} ->
        {:ok,
         %{
           status: status
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
