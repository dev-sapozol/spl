defmodule SplWeb.AuthController do
  use SplWeb, :controller
  alias Spl.{Account}
  alias Spl.Auth.{Guardian, PasswordReset}
  require Logger

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

        Logger.info("Logging in user #{user}")
        Logger.info("Login successfull for password #{password}")
        Logger.info("PASSWORD MATCH #{Bcrypt.verify_pass(password, user.password_hash)}")

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

  def request_password_reset(conn, %{"email" => email}) do
    PasswordReset.request_reset(email)
    json(conn, %{success: true})
  end

  def verify_reset_otp(conn, %{"email" => email, "otp" => otp}) do
    case PasswordReset.verify_otp(email, otp) do
      {:ok, :verified} ->
        PasswordReset.mark_verified(email)
        json(conn, %{success: true})

      {:error, :expired} ->
        conn |> put_status(400) |> json(%{error: "Code expired, request a new one"})

      {:error, :invalid_otp} ->
        conn |> put_status(400) |> json(%{error: "Invalid code"})

      {:error, :too_many_attempts} ->
        conn |> put_status(429) |> json(%{error: "Too many attempts, request a new code"})
    end
  end

  def reset_password(conn, %{"email" => email, "password" => password}) do
    case PasswordReset.reset_password(email, password) do
      {:ok, _} ->
        json(conn, %{success: true})

      {:error, :not_verified} ->
        conn |> put_status(403) |> json(%{error: "OTP not verified"})

      {:error, _} ->
        conn |> put_status(400) |> json(%{error: "Could not reset password"})
    end
  end
end
