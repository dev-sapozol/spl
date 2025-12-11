defmodule Spl.ParseMail.Body do
  alias Spl.ParseMail
  alias Mail.Encoders.QuotedPrintable
  require Logger

  @spec process_body(String.t(), map()) ::
          {String.t(), String.t(), [ParseMail.Attachment.t()]}
  def process_body(body_str, headers) do
    content_type = Map.get(headers, "content-type", "text/plain")
    {main_type, params} = parse_content_type(content_type)
    boundary = params["boundary"] |> clean_boundary()

    cond do
      String.starts_with?(main_type, "multipart/") and not is_nil(boundary) ->
        Logger.debug("Processing multipart email with boundary")
        process_multipart(body_str, boundary, headers)

      true ->
        Logger.debug("Processing single-part email")
        encoding = Map.get(headers, "content-transfer-encoding", "7bit")
        charset = params["charset"] || "utf-8"
        decoded = decode_body(body_str, encoding, charset)

        case main_type do
          "text/html" -> {"", decoded, []}
          _ -> {decoded, "", []}
        end
    end
  end

  defp process_multipart(body_str, boundary, _headers) do
    start_boundary = "--" <> boundary
    end_boundary = start_boundary <> "--"

    parts =
      body_str
      |> String.split(~r/\r?\n?#{Regex.escape(start_boundary)}\r?\n?/)
      |> Enum.drop(1)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.replace_suffix(&1, end_boundary, ""))
      |> Enum.reject(&(&1 == "" or String.trim(&1) == end_boundary))

    Enum.reduce(parts, {"", "", []}, fn part_str, {text_acc, html_acc, attachments_acc} ->
      case process_mime_part(part_str) do
        {:text, content} when text_acc == "" -> {content, html_acc, attachments_acc}
        {:html, content} when html_acc == "" -> {text_acc, content, attachments_acc}
        {:attachment, attachment} -> {text_acc, html_acc, [attachment | attachments_acc]}
        _ -> {text_acc, html_acc, attachments_acc}
      end
    end)
    |> then(fn {text, html, attachment} -> {text, html, Enum.reverse(attachment)} end)
  end

  defp process_mime_part(part_str) do
    case String.split(part_str, ~r/(\r?\n){2}/, parts: 2) do
      [part_header_str, part_body_str] ->
        part_headers = ParseMail.Headers.parse_headers(part_header_str)
        content_type_header = Map.get(part_headers, "content-type", "text/plain")
        {content_type, params} = parse_content_type(content_type_header)
        encoding = Map.get(part_headers, "content-transfer-encoding", "7bit")
        charset = params["charset"] || "utf-8"

        decoded_body = decode_body(part_body_str, encoding, charset)

        cond do
          content_type == "text/plain" ->
            {:text, decoded_body}

          content_type == "text/html" ->
            {:html, decoded_body}

          String.starts_with?(content_type, "image/") or
              String.starts_with?(content_type, "application/") ->
            filename = params["filename"] || "attachment"
            {:attachment, ParseMail.Attachment.new(content_type, filename, decoded_body)}

          true ->
            {:other, decoded_body}
        end

      _ ->
        {:error, :malformed_part}
    end
  end

  @spec parse_content_type(String.t()) :: {String.t(), map()}
  def parse_content_type(header_value) when is_binary(header_value) do
    parts = String.split(header_value, ";") |> Enum.map(&String.trim/1)
    main_type = String.downcase(List.first(parts) || "text/plain")

    params_map =
      Enum.reduce(List.delete_at(parts, 0), %{}, fn param, acc ->
        case String.split(param, "=", parts: 2) do
          [key, value] ->
            clean_value = String.trim(value, "\" ")
            Map.put(acc, String.downcase(String.trim(key)), clean_value)

          _ ->
            acc
        end
      end)

    {main_type, params_map}
  end

  def parse_content_type(_), do: {"text/plain", %{}}

  @spec decode_body(String.t(), String.t(), String.t()) :: String.t()
  def decode_body(body, encoding, charset) do
    normalized_charset =
      charset
      |> to_string()
      |> String.downcase()
      |> String.trim()
      |> String.replace("\"", "")
      |> then(fn cs -> if cs == "", do: "utf-8", else: cs end)

    decoded_binary =
      case String.downcase(to_string(encoding)) do
        "quoted-printable" ->
          try do
            QuotedPrintable.decode(body)
          rescue
            _ -> body
          end

        "base64" ->
          case Base.decode64(body, padding: true) do
            {:ok, bin} -> bin
            :error -> body
          end

        _ ->
          body
      end

    try do
      to_string(decoded_binary)
    rescue
      _ ->
        Logger.warning("Fallback: Forcing binary to UTF-8 for charset #{normalized_charset}")

        decoded_binary
        |> String.codepoints()
        |> Enum.map(fn cp -> if String.valid?(<<cp::utf8>>), do: <<cp::utf8>>, else: "?" end)
        |> Enum.join()
    end
  end

  defp clean_boundary(nil), do: nil

  defp clean_boundary(boundary_str) when is_binary(boundary_str) do
    String.trim(boundary_str, "\"")
  end

  defp clean_boundary(_), do: nil
end
