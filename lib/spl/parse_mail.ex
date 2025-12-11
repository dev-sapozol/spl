defmodule Spl.ParseMail do
  require Logger

  alias Spl.ParseMail
  alias Spl.ParseMail.{Headers, Body, Email}

  @type email_result :: {:ok, Email.t()} | {:error, atom(), String.t()}

  @spec parse_email_content(String.t()) :: email_result()
  def parse_email_content(raw_content) when is_binary(raw_content) do
    try do
      {header_str, body_str} = split_headers_from_body(raw_content)
      headers = Headers.parse_headers(header_str)

      Logger.debug("Email parsed: #{map_size(headers)} headers found")

      email_data = %{
        # Cabeceras de identificacion
        from: Headers.extract_address(headers, "from"),
        to: Headers.extract_address(headers, "to"),
        cc: Headers.extract_address(headers, "cc"),
        bcc: Headers.extract_address(headers, "bcc"),
        reply_to: Headers.extract_address(headers, "reply-to"),
        sender: Headers.extract_address(headers, "sender"),

        # Cabeceras de identificacion
        subject: Headers.get_decoded(headers, "subject", ""),
        message_id: Headers.clean_id(headers["message-id"]),
        references: Headers.parse_references(headers["references"]),
        in_reply_to: Headers.clean_id(headers["in-reply-to"]),

        # Cabeceras de fecha y hora
        date: Headers.parse_date(headers["date"]),

        # Cabeceras de prioridad y estado
        priority: Headers.parse_priority(headers),
        importance: Headers.get_header(headers, "importance"),
        read_receipt: Headers.get_header(headers, "disposition-notification-to"),

        # Cabeceras de contenido
        content_type: Headers.get_header(headers, "content-type", "text/plain"),
        content_transfer_encoding:
          Headers.get_header(headers, "content-transfer-encoding", "7bit"),

        # Cabeceras personalizadas
        custom_headers: Headers.extract_custom_headers(headers),

        # Cuerpo del email
        text_body: "",
        html_body: "",
        attachments: [],

        # Metadata
        raw_readers: headers,
        raw_content: raw_content
      }

      # Procesar el cuerpo segun el content-type
      {text_body, html_body, attachments} = Body.process_body(body_str, headers)

      email_data = %{
        email_data
        | text_body: text_body,
          html_body: html_body,
          attachments: attachments
      }

      {:ok, struct(ParseMail.Email, email_data)}
    rescue
      e in RuntimeError ->
        Logger.error("Error parsing email: #{e.message}")
        {:error, :parse_error, e.message}

      e ->
        Logger.error("Unexpected error: #{inspect(e)}")
        {:error, :unexpected_error, inspect(e)}
    catch
      kind, value ->
        Logger.error("Caught error: #{kind} - #{inspect(value)}")
        {:error, :caught_error, "#{kind}: #{inspect(value)}"}
    end
  end

  @spec split_headers_from_body(String.t()) :: {String.t(), String.t()}
  defp split_headers_from_body(raw_content) do
    case String.split(raw_content, ~r/(\r?\n){2}/, parts: 2) do
      [header_str, body_str] ->
        {header_str, body_str}

      [only_headers] ->
        {only_headers, ""}

      [] ->
        {"", ""}

      other ->
        Logger.warning("Unexpected split result: #{inspect(other)}")
        {raw_content, ""}
    end
  end

  @spec has_attachments?(ParseMail.Email.t()) :: boolean()
  def has_attachments?(%ParseMail.Email{attachments: attachments}),
    do: attachments != [] and attachments != nil

  @spec get_attachments(ParseMail.Email.t()) :: [ParseMail.Attachment.t()]
  def get_attachments(%ParseMail.Email{attachments: attachments}), do: attachments || []

  @spec total_attachments_size(ParseMail.Email.t()) :: non_neg_integer()
  def total_attachments_size(%ParseMail.Email{attachments: attachments}) do
    Enum.reduce(attachments || [], 0, fn att, acc -> att.size + acc end)
  end

  @spec validate_email(ParseMail.Email.t()) :: {:ok, ParseMail.Email.t()} | {:error, [String.t()]}
  def validate_email(email) do
    errors = []

    errors = if is_nil(email.from), do: ["Missing 'from' address" | errors], else: errors
    errors = if Enum.empty?(email.to), do: ["Missing 'to' address" | errors], else: errors
    errors = if String.trim(email.subject) == "", do: ["Missing subject" | errors], else: errors

    case errors do
      [] ->
        {:ok, email}

      errors ->
        {:error, Enum.reverse(errors)}
    end
  end
end
