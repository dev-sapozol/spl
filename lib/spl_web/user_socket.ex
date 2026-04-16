defmodule SplWeb.UserSocket do
  use Phoenix.Socket
  alias Spl.Auth.Guardian

  channel "inbox*", SplWeb.InboxChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        user = Spl.Account.get_user(claims["sub"])
        {:ok, assign(socket, :current_user, user)}

      _ ->
        :error
    end
  end

  @impl true
  def id(socket), do: "users_socket:#{socket.assigns.current_user.id}"
end
