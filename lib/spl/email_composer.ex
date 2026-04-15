defmodule Spl.EmailComposer do
  require Logger

  alias Mail.Encoders.QuotedPrintable
  alias Spl.ParseMail.Headers
  alias Spl.InboxEmail.UtilsFunctions

  # ========================
  # Public API
  # ========================

  @spec compose_email(map()) :: {:ok, binary()} | {:error, term()}
  def compose_email(params) do
    IO.inspect(params, label: "params compose_email")

    try do
      {:ok, generate_raw_email_content(params)}
    rescue
      e ->
        Logger.error("Error composing email: #{inspect(e)}")
        {:error, :composition_failed}
    end
  end

  def compose_reply(params, original_email) do
    try do
      reply_subject = generate_reply_subject(original_email.subject)
      current_date = format_date(DateTime.utc_now())
      original_sender_str = get_formatted_sender(original_email)

      text_body =
        (params.text_body || "") <>
          quote_original_text(original_email.text_body, original_sender_str, current_date)

      html_body =
        String.trim(params.html_body || "") <>
          String.trim(
            quote_original_html(original_email.html_body, original_sender_str, current_date)
          )

      generated_message_id = "<#{generate_message_id(params.from)}>"
      original_message_id_clean = original_email |> Map.get(:original_message_id) |> Headers.clean_id()

      in_reply_to = original_message_id_clean && "<#{original_message_id_clean}>"
      references = generate_references_value(original_email.references, original_message_id_clean)

      {boundary, headers_map} =
        build_headers(%{
          "From" => params.from,
          "To" => params.to,
          "Cc" => params[:cc],
          "Bcc" => params[:bcc],
          "Subject" => reply_subject,
          "Message-ID" => generated_message_id,
          "In-Reply-To" => in_reply_to,
          "References" => references,
          "X-Mailer" => "SPL Email System"
        }, params[:importance])

      raw_email = build_raw_email(headers_map, boundary, text_body, html_body)
      preview = generate_preview(text_body)

      {:ok, %{raw_content: raw_email, headers: headers_map, preview: preview}}
    rescue
      e ->
        Logger.error("Error composing reply: #{inspect(e)}")
        {:error, :reply_composition_failed}
    end
  end

  def compose_forward(params, original_email) do
    try do
      forward_subject = UtilsFunctions.generate_forward_subject(original_email.subject)
      current_date = format_date(DateTime.utc_now())
      original_sender_str = get_formatted_sender(original_email)

      text_body =
        (params.text_body || "") <>
          """


          -------- Forwarded Message --------
          From: #{original_sender_str}
          Date: #{current_date}
          Subject: #{original_email.subject}
          To: #{original_email.to(", ")}
          Cc: #{original_email.cc(", ")}

          """ <>
          (original_email.text_body || "")

      html_body =
        (params.html_body || "") <>
          """
          <hr>
          <p>
          <b>From:</b> #{original_email.from}<br>
          <b>Date:</b> #{current_date}<br>
          <b>Subject:</b> #{original_email.subject}<br>
          <b>To:</b> #{original_email.to(", ")}<br>
          <b>Cc:</b> #{original_email.cc(", ")}<br>
          </p>
          """ <>
          (original_email.html_body || "")

      generated_message_id = "<#{generate_message_id(params.from)}>"

      {boundary, headers_map} =
        build_headers(%{
          "From" => params.from,
          "To" => params.to,
          "Cc" => params[:cc],
          "Bcc" => params[:bcc],
          "Subject" => forward_subject,
          "Message-ID" => generated_message_id
        }, params[:importance])

      raw_email = build_raw_email(headers_map, boundary, text_body, html_body)
      preview = generate_preview(text_body)

      {:ok, %{raw_content: raw_email, headers: headers_map, preview: preview}}
    rescue
      e ->
        Logger.error("Error composing forward: #{inspect(e)}")
        {:error, :forward_composition_failed}
    end
  end

  # ========================
  # Private helpers
  # ========================

  defp generate_raw_email_content(email) do
    email = normalize_email_params(email)

    message_id = email[:message_id] || "<#{generate_message_id(email.from)}>"
    Logger.debug("message_id: #{message_id}")

    {boundary, headers_map} =
      build_headers(%{
        "Return-Path" => UtilsFunctions.extract_email(email.from),
        "From" => email.from,
        "To" => email.to,
        "Cc" => email[:cc],
        "Bcc" => email[:bcc],
        "Subject" => encode_header_if_needed(email.subject),
        "Message-ID" => message_id,
        "Precedence" => "normal"
      }, email[:importance])

    build_raw_email(headers_map, boundary, Map.get(email, :text_body, ""), Map.get(email, :html_body, ""))
  end

  defp build_headers(fields, importance) do
    boundary = "----=_NextPart_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

    headers =
      fields
      |> Map.merge(%{
        "Date" => format_date(DateTime.utc_now()),
        "MIME-Version" => "1.0",
        "Content-Type" => "multipart/alternative; boundary=\"#{boundary}\""
      })
      |> Map.merge(build_priority_headers(importance || "normal"))
      |> Map.reject(fn {_k, v} -> is_nil(v) or v == [] or v == "" end)

    {boundary, headers}
  end

  defp build_priority_headers(importance) do
    case importance do
      "high" -> %{"X-Priority" => "1", "Importance" => "High", "Priority" => "Urgent"}
      "low" -> %{"X-Priority" => "5", "Importance" => "Low", "Priority" => "Low"}
      _ -> %{"X-Priority" => "3", "Importance" => "Normal", "Priority" => "Normal"}
    end
  end

  defp build_raw_email(headers_map, boundary, text_body, html_body) do
    header_lines =
      Enum.map_join(headers_map, "\r\n", fn {k, v} ->
        value_str = if is_list(v), do: Enum.join(v, ", "), else: v
        "#{k}: #{value_str}"
      end)

    encoded_text = encode_quoted_printable(text_body)
    encoded_html = encode_quoted_printable(html_body)

    # Sin indentación para no corromper el MIME
    body =
      "--#{boundary}\r\n" <>
      "Content-Type: text/plain; charset=\"UTF-8\"\r\n" <>
      "Content-Transfer-Encoding: quoted-printable\r\n\r\n" <>
      encoded_text <> "\r\n\r\n" <>
      "--#{boundary}\r\n" <>
      "Content-Type: text/html; charset=\"UTF-8\"\r\n" <>
      "Content-Transfer-Encoding: quoted-printable\r\n\r\n" <>
      encoded_html <> "\r\n\r\n" <>
      "--#{boundary}--\r\n"

    header_lines <> "\r\n\r\n" <> body
  end

  defp encode_header_if_needed(text) do
    if String.match?(text, ~r/[^\x00-\x7F]/) do
      encoded =
        text
        |> :iconv.convert("UTF-8", "ISO-8859-1")
        |> Base.encode16(case: :upper)
        |> String.replace(~r/(..)/, "=$1")

      "=?ISO-8859-1?Q?#{encoded}?="
    else
      text
    end
  end

  defp encode_quoted_printable(text) when is_binary(text) do
    try do
      QuotedPrintable.encode(text)
    rescue
      _ ->
        Logger.warning("Failed to encode quoted-printable, using raw text")
        text
    catch
      _, _ ->
        Logger.warning("Caught error during quoted-printable encoding")
        text
    end
  end

  defp encode_quoted_printable(_other), do: ""

  defp generate_message_id(from) do
    safe_from = from || "unknown@esanpol.com"

    domain =
      case Regex.run(~r/@([^>]+)/, safe_from) do
        [_, d] -> String.trim(d)
        _ -> "spl-system.local"
      end

    random = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    timestamp = :os.system_time(:millisecond)

    "#{random}.#{timestamp}@#{domain}"
  end

  defp format_date(datetime) do
    days = ~w(Mon Tue Wed Thu Fri Sat Sun)
    months = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

    dow = :calendar.day_of_the_week(datetime.year, datetime.month, datetime.day) - 1

    "#{Enum.at(days, dow)}, #{datetime.day} #{Enum.at(months, datetime.month - 1)} " <>
      "#{datetime.year} #{pad(datetime.hour)}:#{pad(datetime.minute)}:#{pad(datetime.second)} +0000"
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"

  defp generate_reply_subject("Re: " <> _ = subject), do: subject
  defp generate_reply_subject(subject), do: "Re: " <> subject

  defp quote_original_text(text, from_str, date_str) do
    clean = to_string(text || "")

    if String.trim(clean) == "" do
      ""
    else
      "\n\nOn #{date_str}, #{from_str} wrote:\n" <>
        (clean |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1)))
    end
  end

  defp quote_original_html(html, from_str, date_str) do
    clean = to_string(html || "")

    if String.trim(clean) == "" do
      ""
    else
      "<br><br>" <>
        "<blockquote style=\"border-left: 2px solid #cccccc; margin-left: 5px; padding-left: 5px;\">" <>
        "On #{date_str}, #{from_str} wrote:<br>#{clean}</blockquote>"
    end
  end

  def generate_preview(content) do
    content
    |> to_string()
    |> then(&Regex.replace(~r/<[^>]+>/, &1, ""))
    |> String.split()
    |> Enum.join(" ")
    |> truncate(100)
  end

  defp truncate(text, max) do
    if String.length(text) > max,
      do: String.slice(text, 0, max - 3) <> "...",
      else: text
  end

  defp generate_references_value(original_refs, new_clean_id) do
    existing =
      if is_nil(original_refs) or String.trim(original_refs) == "" do
        []
      else
        original_refs
        |> String.split(~r/\s+/)
        |> Enum.map(&Headers.clean_id/1)
        |> Enum.reject(&is_nil/1)
      end

    (existing ++ [new_clean_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map_join(" ", &"<#{&1}>")
  end

  defp get_formatted_sender(email) do
    name = Map.get(email, :sender_name)
    address = Map.get(email, :sender_email) || Map.get(email, :from)

    cond do
      is_nil(address) -> "Unknown"
      is_nil(name) or String.trim(name) == "" -> address
      true -> "#{name} <#{address}>"
    end
  end

  defp normalize_email_params(%{from: _} = params), do: params

  defp normalize_email_params(params) do
    from =
      cond do
        is_binary(params[:sender_name]) and is_binary(params[:sender_email]) ->
          "#{params[:sender_name]} <#{params[:sender_email]}>"
        is_binary(params[:sender_email]) ->
          params[:sender_email]
        true ->
          IO.inspect(params, label: "params by NORMALIZE_EMAIL_PARAMS")
      end

    Map.put(params, :from, from)
  end
end
