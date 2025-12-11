defmodule SplWeb.Context do
  @behaviour Plug
  import Plug.Conn
  alias Spl.Auth.Guardian

  # Se ejecuta cuando el pipeline graphql se inicia

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Guardian.verify_and_load_resource(token) do
      Absinthe.Plug.put_options(conn, context: %{current_user: user})
    else
      _ -> Absinthe.Plug.put_options(conn, context: %{})
    end
  end
end
