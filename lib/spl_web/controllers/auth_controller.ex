defmodule SplWeb.AuthController do
  use SplWeb, :controller
  alias Spl.{Account}
  alias Spl.Auth.Guardian

  def register(conn, params) do
    case Account.create_user(params) do
      {:ok, user} ->
        access_token = Account.generate_access_token(user)
        refresh_token = Account.generate_refresh_token(user)

        conn
        |> put_resp_cookie("refresh_token", refresh_token,
          http_only: true,
          secure: true,
          same_site: "Lax",
          max_age: 60 * 60 * 24 * 30
        )
        |> json(%{token: access_token})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Account.authenticate_user(email, password) do
      {:ok, user} ->
        access_token = Account.generate_access_token(user)
        refresh_token = Account.generate_refresh_token(user)

        conn
        |> put_resp_cookie("refresh_token", refresh_token,
          http_only: true,
          secure: true,
          same_site: "Lax",
          # 30 días
          max_age: 60 * 60 * 24 * 30
        )
        |> json(%{token: access_token})

      {:error, _} ->
        conn |> put_status(401) |> json(%{error: "Invalid credentials"})
    end
  end

  def verify_email(conn, %{"email" => email}) do
    case Account.check_email(email) do
      {:ok, exists} ->
        json(conn, %{exists: exists})
    end
  end

  def refresh(conn, _params) do
    case conn.req_cookies["refresh_token"] do
      nil ->
        conn |> put_status(401) |> json(%{error: "No refresh token"})

      refresh_token ->
        case Guardian.decode_and_verify(refresh_token, %{}, token_type: :refresh) do
          {:ok, claims} ->
            user_id = claims["sub"]

            case Account.get_user(user_id) do
              nil ->
                conn |> put_status(401) |> json(%{error: "Invalid user"})

              user ->
                {:ok, new_access, _} =
                  Guardian.encode_and_sign(user, %{}, token_type: :access)

                {:ok, new_refresh, _} =
                  Guardian.encode_and_sign(user, %{}, token_type: :refresh)

                conn
                |> put_resp_cookie("refresh_token", new_refresh,
                  http_only: true,
                  secure: true,
                  same_site: "Lax",
                  max_age: 60 * 60 * 24 * 30
                )
                |> json(%{token: new_access})
            end

          {:error, _reason} ->
            conn |> put_status(401) |> json(%{error: "Invalid refresh token"})
        end
    end
  end

  def change_password(conn, %{"old_password" => old_pw, "new_password" => new_pw}) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(Guardian.Plug.current_token(conn)),
         {:ok, _} <- Account.change_user_password(user, old_pw, new_pw) do
      json(conn, %{message: "Password changed successfully"})
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid password"})
    end
  end
end
