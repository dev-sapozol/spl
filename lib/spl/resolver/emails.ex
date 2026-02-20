defmodule Spl.EmailsResolver do
  require Logger
  alias Spl.{MailBox, InboxEmail}

  def get(%{id: id}, %{context: %{current_user: user}}) do
    Logger.debug("Resolving get_email", metadata: [id: id, user_id: user.id])

    case Spl.EmailCache.get_email_meta(id) do
      {:ok, email} ->
        Logger.debug("Email meta cache HIT", metadata: [email_id: id])
        {:ok, email}

      :error ->
        Logger.debug("Email meta cache MISS", metadata: [email_id: id])

        case MailBox.get_email_full(id, user.id) do
          {:ok, email} ->
            Spl.EmailCache.set_email_data(id, email)
            {:ok, email}

          {:error, _reason} ->
            {:error, "Email not found or access denied"}
        end
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
      {:ok, email} ->
        case MailBox.get_email_full(email.id, current_user.id) do
          {:ok, full_email} ->
            {:ok, full_email}

          {:error, _} ->
            Logger.warning("Email sent but couldn't fetch full details",
              metadata: [email_id: email.id]
            )

            {:ok, email}
        end

      {:error, reason} ->
        {:error, %{message: "Error sending email", details: inspect(reason)}}
    end
  end

  def reply(%{input: input}, %{context: %{current_user: current_user}}) do
    Logger.debug("Resolving reply_email",
      metadata: [parent_id: input.parent_id, user_id: current_user.id]
    )

    case MailBox.get_email(input.parent_id) do
      nil ->
        Logger.error("Original email not found", metadata: [parent_id: input.parent_id])
        {:error, "Original email not found"}

      original_email ->
        case InboxEmail.send_reply(input, original_email, current_user) do
          {:ok, reply_email} ->
            case MailBox.get_email_full(reply_email.id, current_user.id) do
              {:ok, full_email} ->
                {:ok, full_email}

              {:error, _} ->
                Logger.warning("Reply sent but couldn't fetch full details",
                  metadata: [email_id: reply_email.id]
                )

                {:ok, reply_email}
            end

          {:error, reason} ->
            Logger.error("Error replying to email", metadata: [reason: inspect(reason)])
            {:error, reason}
        end
    end
  end

  def delete(%{id: id}, %{context: %{current_user: _current_user}}) do
    case MailBox.delete_email(id) do
      {:ok, email} ->
        {:ok, email}

      {:error, changeset} ->
        Logger.error("Error deleting email", metadata: [id: id])
        {:error, changeset}
    end
  end

  def preload_mailbox(%{limit: limit}, %{context: %{current_user: user}}) do
    {:ok, MailBox.preload_mailbox(user, limit)}
  end

  def resolve_body_url(email, _args, _ctx) do
    {:ok, email.body_url}
  end

  def resolve_raw_url(email, _args, _res) do
    {:ok, email.raw_url}
  end
end
