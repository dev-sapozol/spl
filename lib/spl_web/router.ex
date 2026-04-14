defmodule SplWeb.Router do
  use SplWeb, :router

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

  # API + GraphQL autenticado
  pipeline :api_auth do
    plug :accepts, ["json"]
    plug :put_user_context
    plug :set_http_status
  end

  # ---------------------------------------------------------
  # RUTAS HTML
  # ---------------------------------------------------------

  scope "/health", SplWeb do
    pipe_through :api_auth

    get "/", HealthController, :index
  end

  # ---------------------------------------------------------
  # RUTAS REST
  # ---------------------------------------------------------

  scope "/api", SplWeb do
    pipe_through :api_auth

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
    pipe_through :api_auth

    forward "/graphql",
            Absinthe.Plug,
            schema: SplWeb.Schema,
            upload: false,
            json_codec: Jason
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

    case token && Spl.Auth.Guardian.resource_from_token(token) do
      {:ok, user, _claims} ->
        Absinthe.Plug.put_options(conn, context: %{current_user: user})

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
