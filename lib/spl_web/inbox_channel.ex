defmodule SplWeb.InboxChannel do
  use SplWeb, :channel

  def join("inbox:" <> user_id, _params, socket) do
    if socket.assigns.current_user.id == String.to_integer(user_id) do
      Phoenix.PubSub.subscribe(Spl.PubSub, "inbox:#{user_id}")
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_info({:new_email, email}, socket) do
    push(socket, "new_email", %{
      id: email.id,
      sender_email: email.sender_email,
      sender_name: email.sender_name,
      subject: email.subject,
      preview: email.preview,
      is_read: email.is_read,
      has_attachment: email.has_attachment,
      importance: email.importance,
      folder_id: email.folder_id,
      folder_type: email.folder_type,
      inserted_at: email.inserted_at,
      thread_id: email.thread_id,
      to_addresses: email.to_addresses,
      body_storage_key: email.body_storage_key
    })

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    IO.inspect(msg, label: "CHANNEL RECEIVED")
    {:noreply, socket}
  end
end
