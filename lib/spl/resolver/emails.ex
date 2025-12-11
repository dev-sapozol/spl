defmodule Spl.EmailsResolver do
  alias Spl.{MailBox, InboxEmail}

  def find_emails(%{id: id}, _) do
    case MailBox.get_email(id) do
      nil -> {:error, "Email not found"}
      email -> {:ok, email}
    end
  end

  def list(%{filter: filter}, %{context: %{current_user: _current_user}}) do
    {:ok, MailBox.list_emails(%{filter: filter})}
  end

  @dialyzer {:no_match, create: 2}
  def create(%{input: input}, _info) do
    case InboxEmail.send_email(input, input.user_id) do
      {:ok, email} ->
        {:ok, email}

      {:error, reason} ->
        {:error,
         %{
           message: "Failed to send email",
           detail: inspect(reason)
         }}
    end
  end

  def delete(%{id: id}, context: %{current_user: _current_user}) do
    case MailBox.delete_email(id) do
      {:ok, email} -> {:ok, email}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def get_email_with_sender(%{id: id}, %{context: %{current_user: _current_user}}) do
    {:ok, MailBox.get_email_with_sender(id)}
  end

  def preload_mailbox(%{user_id: user_id, limit: limit}, %{context: %{current_user: _current_user}}) do
    {:ok, MailBox.preload_mailbox(user_id, limit)}
  end
end
