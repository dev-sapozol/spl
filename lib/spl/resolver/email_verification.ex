defmodule Spl.EmailVerificationResolver do
  alias Spl.Sender

  def verify(%{email: email}, _ctx) do
    case Sender.verify_email(email) do
      {:ok, status} ->
        {:ok, %{status: status, message: "verification triggered"}}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def check(%{email: email}, _ctx) do
    case Sender.check_email_status(email) do
      {:ok, status} ->
        {:ok, %{status: status}}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp normalize_error(reason) when is_binary(reason), do: reason
  defp normalize_error(reason), do: inspect(reason)
end
