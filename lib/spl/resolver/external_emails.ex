defmodule Spl.ExternalEmailsResolver do
  alias Spl.Sender
  alias Spl.MailBox

  def verify(%{email: email}, %{context: %{current_user: user}}) do
    with {:ok, _} <- Sender.verify_email(email),
         {:ok, record} <- MailBox.create_external_email(user.id, email) do
      {:ok, %{status: record.status, message: "verification triggered"}}
    else
      {:error, :limit_reached} ->
        {:error, "Limit reached (max 2 emails)"}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        {:error, Enum.join(errors, ", ")}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def check(%{email: email}, %{context: %{current_user: user}}) do
    case MailBox.get_external_email(user.id, email) do
      nil -> {:ok, %{status: :not_found}}
      record -> {:ok, %{status: record.status}}
    end
  end

  def list(_, %{context: %{current_user: user}}) do
    {:ok, MailBox.list_external_emails(user.id)}
  end
end
