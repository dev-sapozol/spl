defmodule Spl.EmailsResolver do
  alias Spl.{MailBox, InboxEmail}

  def get(%{id: id}, _) do
    case MailBox.get_email(id) do
      nil -> {:error, "Email not found"}
      email -> {:ok, email}
    end
  end

  def list(%{filter: filter}, %{context: %{current_user: current_user}}) do
    safe_filter = Map.merge(filter, %{user_id: current_user.id})
    {:ok, MailBox.list_emails(%{filter: safe_filter})}
  end

  @dialyzer {:no_match, create: 2}
  def create(%{input: input}, %{context: %{current_user: current_user}}) do
    input_with_sender =
      input
      |> Map.merge(%{
        user_id: current_user.id,
        sender_email: current_user.email,
        sender_name: current_user.name,
        folder_type: :SYSTEM,
        folder_id: 2
      })

    case InboxEmail.send_email(input_with_sender) do
      {:ok, email} -> {:ok, email}
      {:error, reason} -> {:error, %{message: "Error sending email", details: inspect(reason)}}
    end
  end

  def reply(%{input: input}, %{context: %{current_user: current_user}}) do
    case MailBox.get_email(input.parent_id) do
      nil ->
        {:error, "Original email not found"}

      original_email ->
        InboxEmail.send_reply(input, original_email, current_user)
    end
  end

  def delete(%{id: id}, context: %{current_user: _current_user}) do
    case MailBox.delete_email(id) do
      {:ok, email} -> {:ok, email}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def preload_mailbox(%{user_id: user_id, limit: limit}, %{
        context: %{current_user: _current_user}
      }) do
    {:ok, MailBox.preload_mailbox(user_id, limit)}
  end
end
