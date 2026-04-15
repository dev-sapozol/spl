defmodule Spl.ParseMail.Headers do
  require Logger

  alias Mail.Encoders.QuotedPrintable

  @rfc2047_regex ~r/=\?([^\?]+)\?([QB])\?([^\?]+)\?=/i
  @email_regex ~r/\b([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})\b/

  @doc "Parsea todas las cabeceras del email"
  @spec parse_headers(String.t()) :: map()
  def parse_headers(header_str) when is_binary(header_str) do
    header_str
    |> String.split(~r/\r?\n(?!\s)/)
    |> Enum.map(&String.replace(&1, ~r/\r?\n\s+/, " "))
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key_lower = String.downcase(String.trim(key))
          Map.put(acc, key_lower, String.trim(value))

        _ ->
          acc
      end
    end)
  end

  def parse_headers(_), do: %{}

  @doc "Obtiene una cabecera con valor por defecto"
  @spec get_header(map(), String.t(), String.t()) :: String.t()
  def get_header(headers, key, default \\ "") do
    Map.get(headers, String.downcase(key), default)
  end

  @doc "Obtiene y decodifica una cabecera"
  @spec get_decoded(map(), String.t(), String.t()) :: String.t()
  def get_decoded(headers, key, default \\ "") do
    headers
    |> get_header(key, default)
    |> decode_rfc2047()
  end

  @doc "Extrae una dirección de email de una cabecera"
  @spec extract_address(map(), String.t()) :: [String.t()]
  def extract_address(headers, key) do
    headers
    |> get_decoded(key)
    |> parse_address_list()
  end

  @doc "Extrae una lista de direcciones de email"
  @spec extract_address_list(map(), String.t()) :: [String.t()]
  def extract_address_list(headers, key) do
    headers
    |> get_decoded(key)
    |> parse_address_list()
  end

  @doc "Parsea una dirección simple 'Nombre <email>' o 'email'"
  def parse_single_address(header_value) when is_binary(header_value) do
    case Regex.run(~r/<([^>]+)>/, header_value) do
      [_, email] ->
        String.trim(email)

      nil ->
        case Regex.run(@email_regex, header_value) do
          [_, email] -> String.trim(email)
          [email] -> String.trim(email)
          nil -> nil
        end
    end
  end

  def parse_single_address(_), do: nil

  @doc "Parsea una lista de direcciones separadas por coma"
  @spec parse_address_list(String.t()) :: [String.t()]
  def parse_address_list(header_value) when is_binary(header_value) do
    header_value
    |> String.split(",")
    |> Enum.map(&parse_single_address(String.trim(&1)))
    |> Enum.reject(&is_nil/1)
  end

  def parse_address_list(_), do: []

  @doc "Limpia un ID de cabecera (message-id, in-reply-to)"
  @spec clean_id(String.t() | nil) :: String.t() | nil
  def clean_id(nil), do: nil

  def clean_id(header_id) when is_binary(header_id) do
    cleaned =
      header_id
      |> String.trim()
      |> String.trim_leading("<")
      |> String.trim_trailing(">")
      |> String.trim()

    if cleaned == "", do: nil, else: cleaned
  end

  @doc "Parsea la cabecera References"
  @spec parse_references(String.t() | nil) :: [String.t()]
  def parse_references(nil), do: []

  def parse_references(refs_str) when is_binary(refs_str) do
    refs_str
    |> String.split(~r/\s+/)
    |> Enum.map(&clean_id/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Parsea la fecha del email según RFC 5322"
  @spec parse_date(String.t() | nil) :: DateTime.t() | nil
  def parse_date(nil), do: nil

  def parse_date(date_str) when is_binary(date_str) do
    try do
      case Timex.parse(date_str, "{RFC2822}") do
        {:ok, datetime} ->
          datetime

        {:error, _} ->
          Logger.warning("Could not parse date: #{date_str}")
          nil
      end
    rescue
      _ -> nil
    end
  end

  @doc "Parsea la prioridad del email"
  @spec parse_priority(map()) :: String.t() | nil
  def parse_priority(headers) do
    priority = get_header(headers, "priority")
    x_priority = get_header(headers, "x-priority")

    cond do
      priority != "" -> normalize_priority(priority)
      x_priority != "" -> normalize_x_priority(x_priority)
      true -> nil
    end
  end

  defp normalize_priority(priority) do
    case String.downcase(String.trim(priority)) do
      "urgent" -> "high"
      "normal" -> "normal"
      "non-urgent" -> "low"
      other -> other
    end
  end

  defp normalize_x_priority(x_priority) do
    case String.trim(x_priority) do
      "1" <> _ -> "high"
      "2" <> _ -> "high"
      "3" <> _ -> "normal"
      "4" <> _ -> "low"
      "5" <> _ -> "low"
      _ -> nil
    end
  end

  @doc "Extrae cabeceras personalizadas (X-*)"
  @spec extract_custom_headers(map()) :: map()
  def extract_custom_headers(headers) do
    headers
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, "x-") end)
    |> Enum.into(%{})
  end

  @doc "Decodifica cabeceras RFC 2047"
  @spec decode_rfc2047(String.t()) :: String.t()
  def decode_rfc2047(value) when is_binary(value) do
    Regex.replace(@rfc2047_regex, value, fn _full, charset, encoding, encoded_text ->
      try do
        charset = String.trim(charset)
        encoding = String.upcase(String.trim(encoding))
        encoded_text = String.trim(encoded_text)

        decoded_binary =
          case encoding do
            "Q" ->
              decode_quoted_printable(encoded_text)

            "B" ->
              padded = encoded_text <> String.duplicate("=", rem(String.length(encoded_text), 4))

              case Base.decode64(padded) do
                {:ok, bin} -> bin
                :error -> encoded_text
              end

            _ ->
              encoded_text
          end

        converted =
          try do
            :iconv.convert(charset, "UTF-8", decoded_binary)
          rescue
            _ -> encoded_text
          catch
            _, _ -> encoded_text
          end

        converted
      rescue
        _ -> encoded_text
      catch
        _, _ -> encoded_text
      end
    end)
    |> String.replace("?==?", "")
  end

  def decode_rfc2047(other), do: to_string(other || "")

  defp decode_quoted_printable(text) do
    text
    |> String.replace("_", " ")
    |> then(fn t ->
      try do
        QuotedPrintable.decode(t)
      rescue
        _ -> t
      end
    end)
  end
end
