defmodule SplWeb.Router do
  use SplWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {SplWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :fetch_session
    plug :put_user_context
  end

  scope "/health", SplWeb do
    pipe_through [:api]

    get "/", HealthController, :index
  end

  scope "/api", SplWeb do
    pipe_through [:api, :api_auth]

    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    put "/auth/change-password", AuthController, :change_password
    post "/auth/verify-email", AuthController, :verify_email
    post "/auth/refresh", AuthController, :refresh
  end

  scope "/api" do
    pipe_through [:api, :api_auth]

    forward "/graphql",
            Absinthe.Plug,
            schema: SplWeb.Schema,
            json_codec: Jason
  end

  defp put_user_context(conn, _) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> nil
      end

    case token && Spl.Auth.Guardian.resource_from_token(token) do
      {:ok, user, _claims} ->
        Absinthe.Plug.assign_context(conn, :current_user, user)

      _ ->
        conn
    end
  end
end
