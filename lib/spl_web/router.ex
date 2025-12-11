defmodule SplWeb.Router do
  use SplWeb, :router

  # @enable_graphiql "true"

  # ---------------------------------------------------------
  # PIPELINES
  # ---------------------------------------------------------

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {SplWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # REST API
  pipeline :api do
    plug :accepts, ["json"]
    plug :put_user_context
    plug :set_http_status
  end

  # GraphQL
  pipeline :graphql do
    plug :accepts, ["json"]
    plug SplWeb.Context
  end

  # ---------------------------------------------------------
  # RUTAS HTML
  # ---------------------------------------------------------

  scope "/", SplWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # ---------------------------------------------------------
  # RUTAS REST
  # ---------------------------------------------------------

  scope "/api", SplWeb do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    put "/auth/change-password", AuthController, :change_password
    post "/auth/verify-email", AuthController, :verify_email
    post "/auth/refresh", AuthController, :refresh
  end

  # ---------------------------------------------------------
  # GRAPHQL API
  # ---------------------------------------------------------

  scope "/api" do
    pipe_through :graphql

    forward "/graphql",
            Absinthe.Plug,
            schema: SplWeb.Schema

    forward "/",
            Absinthe.Plug,
            schema: SplWeb.Schema
  end

  # ---------------------------------------------------------
  # HELPERS INTERNOS
  # ---------------------------------------------------------

  defp put_user_context(conn, _) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> nil
      end

    with {:ok, user, _claims} <- Spl.Auth.Guardian.resource_from_token(token) do
      Absinthe.Plug.put_options(conn, context: %{current_user: user})
    else
      _ ->
        Absinthe.Plug.put_options(conn, context: %{})
    end
  end

  defp set_http_status(conn, _) do
    status_code =
      get_in(conn.private[:absinthe][:context], [:http_status_code]) || 200

    Plug.Conn.put_status(conn, status_code)
  end
end
