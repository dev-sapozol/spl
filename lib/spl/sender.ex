defmodule Spl.Sender do
  alias Spl.SignatureV4SES

  def verify_email(email) do
    case SignatureV4SES.verify_email_identity(email) do
      {:ok, _} -> {:ok, "pending"}
      error -> {error, IO.inspect(error)}
    end
  end

  def check_email_status(email) do
    case SignatureV4SES.get_email_verification_status(email) do
      {:ok, status} -> {:ok, normalize(status)}
      error -> error
    end
  end

  defp normalize("Success"), do: "verified"
  defp normalize("Pending"), do: "pending"
  defp normalize("Failed"), do: "failed"
  defp normalize(_), do: "unknown"
end
