defmodule Spl.ParseMail.Validators do
  alias Spl.ParseMail.Email

  @email_regex ~r/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/

  @doc "Valida si una dirección de email es válida"
  @spec is_valid_email?(String.t()) :: boolean()
  def is_valid_email?(email) when is_binary(email) do
    Regex.match?(@email_regex, String.trim(email))
  end

  def is_valid_email?(_), do: false

  @doc "Valida una lista de direcciones de email"
  @spec validate_email_list([String.t()]) :: {:ok, [String.t()]} | {:error, [String.t()]}
  def validate_email_list(emails) do
    invalid = Enum.reject(emails, &is_valid_email?/1)

    case invalid do
      [] -> {:ok, emails}
      _ -> {:error, invalid}
    end
  end

  @doc "Valida un email completo"
  @spec validate_email(Email.t()) :: {:ok, Email.t()} | {:error, [String.t()]}
  def validate_email(email) do
    errors = []

    errors = if is_nil(email.from), do: ["Missing 'from' address" | errors], else: errors
    errors = if Enum.empty?(email.to), do: ["Missing 'to' address" | errors], else: errors
    errors = if String.trim(email.subject) == "", do: ["Missing subject" | errors], else: errors

    case errors do
      [] -> {:ok, email}
      errors -> {:error, Enum.reverse(errors)}
    end
  end
end
