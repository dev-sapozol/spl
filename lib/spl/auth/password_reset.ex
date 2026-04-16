defmodule Spl.Auth.PasswordReset do
  alias Spl.{Cache, Account}

  # 15 min
  @otp_ttl 900
  @max_attempts 5

  defp otp_key(email), do: "pwd_reset::otp:#{email}"
  defp attemps_key(email), do: "pwd_reset::attempts:#{email}"
  defp verified_key(email), do: "pwd_reset:verified:#{email}"

  def request_reset(email) do
    if not String.ends_with?(email, "@esanpol.xyz") do
      :ok
    else
      case Account.get_user_by_email(email) do
        nil ->
          :ok

        user ->
          IO.inspect(user.recovery_email, label: "recovery_email")
          otp = :crypto.strong_rand_bytes(3) |> Base.encode16() |> String.slice(0, 6)
          Cache.set(otp_key(email), %{otp: otp}, @otp_ttl)
          Cache.del(attemps_key(email))
          send_otp_email(user.recovery_email, otp, user.name)
      end
    end
  end

  def verify_otp(email, input_otp) do
    attemps = get_attempts(email)

    cond do
      attemps >= @max_attempts ->
        {:error, :too_many_attempts}

      true ->
        case Cache.get(otp_key(email)) do
          {:ok, %{otp: stored_otp}} when stored_otp == input_otp ->
            {:ok, :verified}

          {:ok, _} ->
            Cache.set(attemps_key(email), attemps + 1, @otp_ttl)
            {:error, :invalid_otp}

          :error ->
            {:error, :expired}
        end
    end
  end

  def mark_verified(email) do
    Cache.del(otp_key(email))
    Cache.del(attemps_key(email))
    # 10 para completar reset
    Cache.set(verified_key(email), true, 600)
  end

  def reset_password(email, new_password) do
    case Cache.get(verified_key(email)) do
      {:ok, true} ->
        case Account.get_user_by_email(email) do
          nil ->
            {:error, :not_found}

          user ->
            result = Account.reset_user_password(user, new_password)
            Cache.del(verified_key(email))
            result
        end

      _ ->
        {:error, :not_verified}
    end
  end

  def get_attempts(email) do
    case Cache.get(attemps_key(email)) do
      {:ok, n} when is_integer(n) -> n
      _ -> 0
    end
  end

  defp send_otp_email(recovery_email, otp, name) do
    IO.inspect([recovery_email, otp, name], label: "send_otp_email")

    html = """
    <div style="font-family: Arial, sans-serif; max-width: 480px; margin: auto; padding: 32px;">
      <h2 style="color: #0067b8;">Esanpol</h2>
      <p>Hi #{name},</p>
      <p>You requested to reset your password. Use this code:</p>
      <div style="
        font-size: 36px;
        font-weight: bold;
        letter-spacing: 12px;
        text-align: center;
        padding: 24px;
        background: #f4f4f4;
        border-radius: 8px;
        margin: 24px 0;
        color: #111;
      ">#{otp}</div>
      <p style="color: #666; font-size: 13px;">
        This code expires in <strong>15 minutes</strong>.<br>
        If you didn't request this, you can ignore this email.
      </p>
    </div>
    """

    Spl.SignatureV4SES.send_email(%{
      to: recovery_email,
      subject: "Your Esanpol password reset code: #{otp}",
      html_body: html,
      text_body: "Your Esanpol password reset code: #{otp}"
    })
  end
end
