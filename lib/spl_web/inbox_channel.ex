defmodule SplWeb.InboxChannel do
  use SplWeb, :channel

  def join("inbox:" <> user_id, _params, socket) do
    if socket.assigns.current_user.id == String.to_integer(user_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_info({:new_email, email}, socket) do
    push(socket, "new_email", %{
      id: email.id,
      subject: email.subject,
      from: email.from,
      preview: email.preview,
      received_at: email.inserted_at
    })

    {:noreply, socket}
  end
end
