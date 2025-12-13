defmodule Spl.EmailComposer do
  require Logger

  alias Mail.Encoders.QuotedPrintable
  alias Spl.ParseMail.Headers
  alias Spl.InboxEmail.UtilsFunctions

  @spec compose_email(map()) :: {:ok, binary()} | {:error, term()}
  def compose_email(params) do
    IO.inspect(params, label: "params compose_email")

    try do
      raw_email = generate_raw_email_content(params)
      {:ok, raw_email}
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

      quoted_text =
        quote_original_text(original_email.text_body, original_sender_str, current_date)

      reply_text_body_full = (params.text_body || "") <> quoted_text

      quoted_html =
        quote_original_html(original_email.html_body, original_sender_str, current_date)

      reply_html_body_full =
        String.trim(params.html_body || "") <> String.trim(quoted_html)

      generated_message_id = "<#{generate_message_id(params.from)}>"
      raw_id = Map.get(original_email, :original_message_id)
      original_message_id_clean = Headers.clean_id(raw_id)

      calculated_in_reply_to =
        if original_message_id_clean, do: "<#{original_message_id_clean}>", else: nil

      calculated_references =
        generate_references_value(original_email.references, original_message_id_clean)

      headers_map =
        build_reply_headers(
          params,
          reply_subject,
          generated_message_id,
          calculated_in_reply_to,
          calculated_references
        )

      raw_email = build_raw_email(headers_map, reply_text_body_full, reply_html_body_full)
      preview = generate_preview(reply_text_body_full)

      {:ok,
       %{
         raw_content: raw_email,
         headers: headers_map,
         preview: preview
       }}
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

      forward_header_text = """
      \n\n-------- Forwarded Message --------
      From: #{original_sender_str}
      Date: #{current_date}
      Subject: #{original_email.subject}
      To: #{original_email.to(", ")}
      Cc: #{original_email.cc(", ")}
      \n
      """

      forward_text_body_full =
        (params.text_body || "") <> forward_header_text <> (original_email.text_body || "")

      forward_html_body = """
      <hr>
      <p>
      <b>From:</b> #{original_email.from}<br>
      <b>Date:</b> #{current_date}<br>
      <b>Subject:</b> #{original_email.subject}<br>
      <b>To:</b> #{original_email.to(", ")}<br>
      <b>Cc:</b> #{original_email.cc(", ")}<br>
      </p>
      """

      forward_html_body_full =
        (params.html_body || "") <> forward_html_body <> (original_email.html_body || "")

      generated_message_id = "<#{generate_message_id(params.from)}>"

      headers_map =
        build_forward_headers(
          params,
          forward_subject,
          generated_message_id
        )

      raw_email = build_raw_email(headers_map, forward_text_body_full, forward_html_body_full)
      preview = generate_preview(forward_text_body_full)

      {:ok,
       %{
         raw_content: raw_email,
         headers: headers_map,
         preview: preview
       }}
    rescue
      e ->
        Logger.error("Error composing forward: #{inspect(e)}")
        {:error, :forward_composition_failed}
    end
  end

  defp generate_raw_email_content(email) do
    Logger.debug("Generating raw email content: #{inspect(email)}")

    email = normalize_email_params(email)

    text_body = Map.get(email, :text_body, "")
    html_body = Map.get(email, :html_body, "")

    message_id = email[:message_id] || "<#{generate_message_id(email.from)}>"
    Logger.debug("message_id: #{message_id}")
    date = format_date(DateTime.utc_now())

    boundary = "----=_NextPart_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

    headers_map = build_email_headers(email, message_id, date, boundary)
    build_raw_email(headers_map, text_body, html_body)
  end

  defp build_email_headers(email, message_id, date, boundary) do
    priority_headers = build_priority_headers(email[:importance] || "normal")

    %{
      "Return-Path" => UtilsFunctions.extract_email(email.from),
      "From" => email.from,
      "To" => email.to,
      "Cc" => email[:cc],
      "Bcc" => email[:bcc],
      "Subject" => encode_header_if_needed(email.subject),
      "Date" => date,
      "Message-ID" => message_id,
      "MIME-Version" => "1.0",
      "Content-Type" => "multipart/alternative; boundary=\"#{boundary}\"",
      "Precedence" => "normal"
    }
    |> Map.merge(priority_headers)
    |> Map.reject(fn {_k, v} -> is_nil(v) or v == [] or v == "" end)
  end

  defp build_reply_headers(params, subject, message_id, in_reply_to, references) do
    priority_headers = build_priority_headers(params[:importance] || "normal")
    boundary = "----=_NextPart_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

    %{
      "From" => params.from,
      "To" => params.to,
      "Cc" => params[:cc],
      "Bcc" => params[:bcc],
      "Subject" => subject,
      "Date" => format_date(DateTime.utc_now()),
      "Message-ID" => message_id,
      "In-Reply-To" => in_reply_to,
      "References" => references,
      "MIME-Version" => "1.0",
      "Content-Type" => "multipart/alternative; boundary=\"#{boundary}\"",
      "X-Mailer" => "SPL Email System",
      "Precedence" => "normal"
    }
    |> Map.merge(priority_headers)
    |> Map.reject(fn {_k, v} -> is_nil(v) or v == [] or v == "" end)
  end

  defp build_forward_headers(params, subject, message_id) do
    priority_headers = build_priority_headers(params[:importance] || "normal")
    boundary = "----=_NextPart_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

    %{
      "From" => params.from,
      "To" => params.to,
      "Cc" => params[:cc],
      "Bcc" => params[:bcc],
      "Subject" => subject,
      "Date" => format_date(DateTime.utc_now()),
      "Message-ID" => message_id,
      "MIME-Version" => "1.0",
      "Content-Type" => "multipart/alternative; boundary=\"#{boundary}\"",
      "Precedence" => "normal"
    }
    |> Map.merge(priority_headers)
    |> Map.reject(fn {_k, v} -> is_nil(v) or v == [] or v == "" end)
  end

  defp build_priority_headers(importance) do
    case importance do
      "high" -> %{"X-Priority" => "1", "Importance" => "High", "Priority" => "Urgent"}
      "low" -> %{"X-Priority" => "5", "Importance" => "Low", "Priority" => "Low"}
      _ -> %{"X-Priority" => "3", "Importance" => "Normal", "Priority" => "Normal"}
    end
  end

  defp build_raw_email(headers_map, text_body, html_body) do
    boundary = extract_boundary(headers_map["Content-Type"])

    header_lines =
      Enum.map(headers_map, fn {k, v} ->
        value_str = if is_list(v), do: Enum.join(v, ", "), else: v
        "#{k}: #{value_str}"
      end)

    encoded_text_part = encode_quoted_printable(text_body)
    encoded_html_part = encode_quoted_printable(html_body)

    multipart_body = """
    --#{boundary}
    Content-Type: text/plain; charset="UTF-8"
    Content-Transfer-Encoding: quoted-printable

    #{encoded_text_part}

    --#{boundary}
    Content-Type: text/html; charset="UTF-8"
    Content-Transfer-Encoding: quoted-printable

    #{encoded_html_part}

    --#{boundary}--
    """

    Enum.join(header_lines, "\r\n") <> "\r\n\r\n" <> multipart_body
  end

  defp extract_boundary(content_type) do
    case Regex.run(~r/boundary="([^"]+)"/, content_type) do
      [_, boundary] -> boundary
      _ -> "----=_NextPart_default"
    end
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
      _exception ->
        Logger.warning("Failed to encode quoted-printable, using raw text")
        text
    catch
      _kind, _value ->
        Logger.warning("Caught error during quoted-printable encoding")
        text
    end
  end

  defp encode_quoted_printable(_other), do: ""

  defp generate_message_id(from) do
    safe_from = from || "unknown@esanpol.com"

    email =
      case Regex.run(~r/<(.+?)>/, from, capture: :all_but_first) do
        [clean] ->
          clean

        _ ->
          case Regex.run(~r/[\w.+-]+@\w[\w.-]+\.\w+/, from) do
            [clean_email] -> clean_email
            # Fallback seguro
            _ -> "unknown@example.com"
          end
      end

    domain =
      case Regex.run(~r/@([^>]+)/, safe_from) do
        [_, d] -> String.trim(d)
        _ -> "spl-system.local"
      end

    random_string = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    timestamp = :os.system_time(:millisecond)

    "#{random_string}.#{timestamp}@#{domain}"
  end

  defp format_date(datetime) do
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ]

    {year, month, day} = {datetime.year, datetime.month, datetime.day}
    {hour, minute, second} = {datetime.hour, datetime.minute, datetime.second}

    day_of_week = :calendar.day_of_the_week(year, month, day) - 1

    "#{Enum.at(days, day_of_week)}, #{day} #{Enum.at(months, month - 1)} #{year} #{pad(hour)}:#{pad(minute)}:#{pad(second)} +0000"
  end

  defp pad(number) when number < 10, do: "0#{number}"
  defp pad(number), do: "#{number}"

  defp generate_reply_subject(original_subject) do
    if String.starts_with?(original_subject, "Re: ") do
      original_subject
    else
      "Re: " <> original_subject
    end
  end

  defp quote_original_text(text, from_email, date_str) do
    clean_text = to_string(text || "")

    if String.trim(clean_text) == "" do
      ""
    else
      header = "\n\nOn #{date_str}, #{from_email} wrote:\n"

      body =
        clean_text
        |> String.split("\n")
        |> Enum.map(fn line -> "> " <> line end)
        |> Enum.join("\n")

      header <> body
    end
  end

  @spec quote_original_html(String.t() | nil, String.t(), String.t()) ::
          String.t() | nil
  defp quote_original_html(html, from_email, date_str) do
    clean_html = to_string(html || "")

    if String.trim(clean_html) == "" do
      ""
    else
      """
      <br><br>
      <blockquote style="border-left: 2px solid #cccccc; margin-left: 5px; padding-left: 5px;">
        On #{date_str}, #{from_email} wrote:<br>
        #{clean_html}
      </blockquote>
      """
    end
  end

  def generate_preview(content) do
    plain_text =
      case content do
        nil -> ""
        text when is_binary(text) -> Regex.replace(~r/<[^>]+>/, text, "")
        other -> Regex.replace(~r/<[^>]+>/, to_string(other), "")
      end

    normalized_text =
      plain_text
      |> String.split()
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    max_len = 100
    ellipsis = "..."

    if String.length(normalized_text) > max_len do
      String.slice(normalized_text, 0, max_len - String.length(ellipsis)) <> ellipsis
    else
      normalized_text
    end
  end

  defp generate_references_value(original_references_str, new_clean_id) do
    existing_clean_refs =
      if is_nil(original_references_str) or String.trim(original_references_str) == "" do
        []
      else
        original_references_str
        |> String.split(~r/\s+/)
        |> Enum.map(&Headers.clean_id/1)
        |> Enum.reject(&is_nil/1)
      end

    all_clean_refs =
      (existing_clean_refs ++ [new_clean_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    all_clean_refs
    |> Enum.map(fn id -> "<#{id}>" end)
    |> Enum.join(" ")
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

  defp normalize_email_params(params) do
    if Map.has_key?(params, :from) do
      params
    else
      sender_name = params[:sender_name]
      sender_email = params[:sender_email]

      from_value =
        cond do
          is_binary(sender_name) and is_binary(sender_email) ->
            "#{sender_name} <#{sender_email}>"

          is_binary(sender_email) ->
            sender_email

          true ->
            "unknown@spl-system.com"
        end

      Map.put(params, :from, from_value)
    end
  end
end
