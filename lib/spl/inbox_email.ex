defmodule Spl.InboxEmail do
  import Ecto.Query
  use GenServer
  require Logger

  alias Spl.Account
  alias Spl.MailBox.Emails
  alias ExAws.{SES, SQS, S3}
  alias Mail.Encoders.QuotedPrintable
  alias Spl.{AwsBuilder, Repo, MailBox, ParseMail, Account}
  alias Spl.ParseMail.{Email, Headers}
  alias Spl.InboxEmail.{UtilsFunctions, EmailComposer}

  @inbox_type %{received: 0, sent: 1, draft: 2}
  @statuses %{unread: 0, sent: 1, failed: 99}
  @region "us-east-1"
  @s3_spl "spl-ses-bucket-dev"

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    listener_messages_sqs()
    {:ok, %{}}
  end

  def listener_messages_sqs() do
    Logger.info("processing genserver")
    Process.send_after(self(), :process_messages, 15_000)
  end

  def handle_info(:process_messages, state) do
    listener_messages_sqs()
    process_messages()
    {:noreply, state}
  end

  def process_messages do
    queue_url = AwsBuilder.build_ses_s3_queue()
    Logger.debug("SQS: #{inspect(queue_url)}")
    Logger.debug("Processing messages from SQS", metadata: [queue_url: queue_url])

    queue_url
    |> SQS.receive_message(max_number_of_messages: 10)
    |> ExAws.request(region: @region)
    |> case do
      {:ok, response} ->
        handle_messages(response.body, queue_url)

      {:error, error} ->
        Logger.error("Error receiving messages from SQS: #{inspect(error)}")
    end
  end

  defp handle_messages(%{messages: []}, _queue_uel) do
    Logger.debug("No messages received from SQS")
  end

  defp handle_messages(%{messages: messages}, queue_url)
       when is_list(messages) and length(messages) > 0 do
    messages
    |> Enum.map(&Task.async(fn -> process_single_message(&1, queue_url) end))
    |> Task.await_many(:infinity)
  end

  defp process_single_message(message, queue_url) do
    case Jason.decode(message.body) do
      {:ok, %{"Message" => raw_message}} ->
        Logger.debug("Processing SQS message", metadata: [message_id: message.message_id])

        case Jason.decode(raw_message) do
          {:ok, data} ->
            delete_message(message.receipt_handle, queue_url)
            process_data_email(data)

          _ ->
            Logger.info("RAW MIME received, decoding Base64")
            delete_message(message.receipt_handle, queue_url)

            case Base.decode64(raw_message) do
              {:ok, raw_eml_body} ->
                register_email(raw_eml_body, nil, nil)

              {:error, reason} ->
                Logger.error("Error decoding RAW MIME base64: #{inspect(reason)}")
                {:error, :invalid_raw_message}
            end
        end

      {:error, reason} ->
        Logger.error("Error decoding SQS wrapper: #{inspect(reason)}")
    end
  end

  defp delete_message(receipt_handle, queue_url) do
    SQS.delete_message(
      queue_url,
      receipt_handle
    )
    |> ExAws.request(region: @region)
  end

  # PROCESSING

def process_data_email(data) do
  Logger.debug("Processing email data from SES")

  if Map.has_key?(data, "content") do
    Logger.info("Detected RAW MIME email from SES")

    case Base.decode64(data["content"]) do
      {:ok, raw_eml_body} ->
        register_email(raw_eml_body, nil, nil)

      {:error, reason} ->
        Logger.error("Error decoding RAW MIME Base64: #{inspect(reason)}")
        {:error, :invalid_raw_mime}
    end

  else
    with {:ok, from_email} <- extract_from_email(data),
         {:ok, timestamp} <- extract_timestamp(data),
         {:ok, message_id} <- extract_message_id(data),
         {:ok, object_key, bucket_name} <- extract_s3_location(data) do

      case validate_email_sent(from_email, timestamp) do
        sent_email_id when not is_nil(sent_email_id) ->
          update_sent_email(sent_email_id, message_id, object_key)

        nil ->
          download_and_register_email(bucket_name, object_key, message_id)
      end
    else
      {:error, reason} ->
        Logger.error("Error processing email data: #{inspect(reason)}")
        {:error, reason}
    end
  end
end


  defp extract_from_email(data) do
    case get_in(data, ["mail", "commonHeaders", "from"]) do
      [from_email | _] -> {:ok, from_email}
      # _ -> {:error, :invalid_from_email}
      _ -> {:error, inspect(data)}
    end
  end

  defp extract_timestamp(data) do
    case get_in(data, ["mail", "timestamp"]) do
      timestamp_str when is_binary(timestamp_str) ->
        case DateTime.from_iso8601(timestamp_str) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, _} -> {:error, :invalid_timestamp}
        end

      _ ->
        {:error, :missing_timestamp}
    end
  end

  defp extract_message_id(data) do
    case get_in(data, ["mail", "commonHeaders", "messageId"]) do
      message_id when is_binary(message_id) ->
        {:ok, Headers.clean_id(message_id)}

      _ ->
        {:error, :missing_message_id}
    end
  end

  defp extract_s3_location(data) do
    with object_key when is_binary(object_key) <-
           get_in(data, ["receipt", "action", "objectKey"]),
         bucket_name when is_binary(bucket_name) <-
           get_in(data, ["receipt", "action", "bucketName"]) do
      {:ok, object_key, bucket_name}
    else
      # _ -> {:error, :missing_s3_location}
      _ -> {:error, inspect(data)}
    end
  end

  defp validate_email_sent(email, timestamp) do
    min_time = DateTime.add(timestamp, -60, :second)
    naive_min_time = DateTime.to_naive(min_time)
    naive_timestamp = DateTime.to_naive(timestamp)

    from(ei in Emails,
      where: ei.from == ^email,
      where: ei.inserted_at >= ^naive_min_time and ei.inserted_at <= ^naive_timestamp,
      select: ei.id
    )
    |> Spl.Repo.one()
  end

  defp update_sent_email(email_id, message_id, s3_url) do
    case Repo.get(Emails, email_id) do
      %Emails{} = email ->
        Logger.info("Updating sent email with S3 URL", metadata: [email_id: email_id])

        Emails.changeset(email, %{
          message_id: message_id,
          s3_url: s3_url,
          inbox_type: @inbox_type.sent
        })
        |> Repo.update()

      nil ->
        Logger.warning("Email not found for update", metadata: [email_id: email_id])
        {:error, :not_found}
    end
  end

  defp download_and_register_email(bucket_name, object_key, message_id) do
    case UtilsFunctions.download_file_from_s3(bucket_name, object_key) do
      {:ok, raw_eml_body} ->
        register_email(raw_eml_body, object_key, message_id)

      {:error, reason} ->
        Logger.error("Error downloading email from S3", metadata: [reason: inspect(reason)])
        {:error, :download_failed}
    end
  end

  # EMAIL REGISTRATION

  def register_email(raw_eml_body, s3_url, _message_id_from_header) do
    case ParseMail.parse_email_content(raw_eml_body) do
      {:ok, %Email{} = parsed_email} ->
        Logger.info("Succesfully parsed received email")
        thread_id = find_or_create_thread_id(parsed_email)

        create_received_email_record(parsed_email, thread_id, s3_url)

      {:error, _type, reason} ->
        Logger.error("Error parsing email: #{inspect(reason)}")
        {:error, :parse_failed}
    end
  end

  defp create_received_email_record(parsed_email, thread_id, s3_url) do

    user_id = Account.get_user_id_by_email(parsed_email.to)

    received_email_attrs = %{
      user_id: user_id,
      to: UtilsFunctions.list_to_string(parsed_email.to),
      cc: UtilsFunctions.list_to_string(parsed_email.cc),
      bcc: UtilsFunctions.list_to_string(parsed_email.bcc),
      subject: parsed_email.subject,
      preview: EmailComposer.generate_preview(parsed_email.text_body || parsed_email.html_body),
      s3_url: s3_url,
      inbox_type: @inbox_type.received,
      status: @statuses.unread,
      importance: extract_importance(parsed_email),
      message_id: parsed_email.message_id,
      reference_header: parsed_email.references,
      in_reply_to_header: parsed_email.in_reply_to,
      thread_id: thread_id,
      text_body: parsed_email.text_body,
      html_body: parsed_email.html_body,
      has_attachments: not Enum.empty?(parsed_email.attachments),
      folder_id: 1,
      folder_type: :SYSTEM
    }

    case MailBox.create_email(received_email_attrs) do
      {:ok, new_email} ->
        Logger.info("Succesfully registered received email", metadata: [email_id: new_email.id])
        {:ok, new_email}

      {:error, reason} ->
        Logger.error("Error registering received email: #{inspect(reason)}")
        {:error, :registration_failed}
    end
  end

  defp extract_importance(parsed_email) do
    case parsed_email.importance do
      "high" -> 2
      "low" -> 1
      _ -> 0
    end
  end

  # EMAIL SENDING

  @dialyzer {:no_match, send_email: 2}
  @spec send_email(map(), binary()) ::
          {:ok, Spl.MailBox.Emails.t()} | {:error, term()}

  def send_email(params, user_id) do
    Logger.debug("Processing email send and params", metadata: [params: params])

    user = Account.get_user(user_id)
    from = Account.build_display_name(user)

    thread_id = Ecto.UUID.generate()
    Logger.info("Sending email", metadata: [thread_id: thread_id])

    with {:ok, raw_email} <- EmailComposer.compose_email(params, from),
         {:ok, _ses_response} <-
           send_raw_email(raw_email, from, params.to, params[:cc], params[:bcc]),
         {:ok, email_imbox} <- create_email_imbox_record(params, user_id, thread_id) do
      {:ok, email_imbox}
    else
      {:error, reason} ->
        Logger.error("Error sending email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # EMAIL REPLY

  def reply_email(params) do
    Logger.info("Processing email reply", metadata: [original_email_id: params.original_email_id])

    with %Emails{} = original_email <- Repo.get(Emails, params.original_email_id),
         true <- !is_nil(original_email.s3_url),
         {:ok, raw_eml_body} <-
           UtilsFunctions.download_file_from_s3(@s3_spl, original_email.s3_url),
         {:ok, %Email{} = parsed_original} <- ParseMail.parse_email_content(raw_eml_body),
         true <- !is_nil(parsed_original.message_id) and !is_nil(parsed_original.from) do
      process_reply(params, original_email, parsed_original)
    else
      error ->
        handle_reply_error(error)
    end
  end

  @dialyzer [nowarn_function: [process_reply: 3]]
  defp process_reply(params, original_email, parsed_original) do
    with {:ok, reply_data} <- EmailComposer.compose_reply(params, parsed_original),
         {:ok, s3_url} <- upload_reply_to_s3(reply_data.raw_content),
         {:ok, new_reply} <- create_reply_record(params, original_email, reply_data, s3_url),
         {:ok, _} <-
           send_raw_email(
             reply_data.raw_content,
             params.from,
             params.to,
             params[:cc],
             params[:bcc]
           ) do
      Logger.info("Reply sent successfully", metadata: [reply_id: new_reply.id])
      {:ok, new_reply}
    else
      {:error, reason} ->
        Logger.error("Error processing reply: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upload_reply_to_s3(raw_content) do
    s3_key = generate_s3_key()
    UtilsFunctions.upload_file_to_s3(@s3_spl, s3_key, raw_content)
  end

  defp create_reply_record(params, original_email, reply_data, s3_url) do
    reply_attrs = %{
      user_id: params.user_id,
      from: params.from,
      to: UtilsFunctions.list_to_string(params.to),
      cc: UtilsFunctions.list_to_string(params[:cc]),
      bcc: UtilsFunctions.list_to_string(params[:bcc]),
      subject: reply_data.headers["Subject"],
      preview: reply_data.preview,
      s3_url: s3_url,
      inbox_type: @inbox_type.sent,
      status: @statuses.unread,
      importance: params[:importance] || "normal",
      message_id: Headers.clean_id(reply_data.headers["Message-ID"]),
      reference_header: reply_data.headers["References"],
      in_reply_to_header: reply_data.headers["In-Reply-To"],
      thread_id: original_email.thread_id,
      text_body: params.text_body,
      html_body: params.html_body
    }

    MailBox.create_email(reply_attrs)
  end

  defp handle_reply_error({:error, _type, message}) do
    Logger.error("Reply parse error: #{message}")
    {:error, :parse_failed}
  end

  defp handle_reply_error({:error, reason}) do
    Logger.error("Reply error: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_reply_error(nil) do
    Logger.error("Original email not found")
    {:error, :not_found}
  end

  defp handle_reply_error(false) do
    Logger.error("Reply validation failed")
    {:error, :validation_failed}
  end

  # EMAIL FORWARD

  def forward_email(params) do
    Logger.info("Processing email forward",
      metadata: [original_email_id: params.original_email_id]
    )

    with %Emails{} = original_email <- Repo.get(Emails, params.original_email_id),
         true <- !is_nil(original_email.s3_url),
         {:ok, raw_eml_body} <-
           UtilsFunctions.download_file_from_s3(@s3_spl, original_email.s3_url),
         {:ok, %Email{} = parsed_original} <- ParseMail.parse_email_content(raw_eml_body) do
      process_forward(params, original_email, parsed_original)
    else
      error ->
        handle_forward_error(error)
    end
  end

  @dialyzer [nowarn_function: [process_forward: 3]]
  defp process_forward(params, original_email, parsed_original) do
    with {:ok, forward_data} <- EmailComposer.compose_forward(params, parsed_original),
         {:ok, s3_url} <- upload_reply_to_s3(forward_data.raw_content),
         {:ok, new_forward} <- create_forward_record(params, original_email, forward_data, s3_url) do
      case send_raw_email(
             forward_data.raw_content,
             params.from,
             params.to,
             params[:cc],
             params[:bcc]
           ) do
        {:ok, _resp} ->
          Logger.info("Forward sent successfully", metadata: [forward_id: new_forward.id])
          {:ok, new_forward}

        {:error, :no_valid_destinations} ->
          Logger.error("No valid destinations for forward")
          {:error, :no_valid_destinations}

        {:error, reason} ->
          Logger.error("Error processing forward: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Error processing forward: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_forward_record(params, _original_email, forward_data, s3_url) do
    forward_attrs = %{
      user_id: params.user_id,
      from: params.from,
      to: UtilsFunctions.list_to_string(params.to),
      cc: UtilsFunctions.list_to_string(params[:cc]),
      bcc: UtilsFunctions.list_to_string(params[:bcc]),
      subject: forward_data.headers["Subject"],
      preview: forward_data.preview,
      s3_url: s3_url,
      inbox_type: @inbox_type.sent,
      status: @statuses.unread,
      importance: params[:importance] || "normal",
      message_id: Headers.clean_id(forward_data.headers["Message-ID"]),
      reference_header: nil,
      in_reply_to_header: nil,
      thread_id: Ecto.UUID.generate(),
      text_body: params.text_body,
      html_body: params.html_body
    }

    MailBox.create_email(forward_attrs)
  end

  defp handle_forward_error({:error, reason, details}) do
    Logger.error("Forward error: #{inspect(reason)} - #{details}")
    {:error, reason}
  end

  defp handle_forward_error({:error, reason}) do
    Logger.error("Forward error: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_forward_error(nil) do
    Logger.error("Original email not found")
    {:error, :not_found}
  end

  defp handle_forward_error(false) do
    Logger.error("Forward validation failed")
    {:error, :validation_failed}
  end

  # THREAD MANAGEMENT

  def find_or_create_thread_id(email) do
    ref_ids = extract_ids_from_header(email.references)
    in_reply_to_ids = extract_ids_from_header(email.in_reply_to)
    message_id = email.message_id

    search_ids = (ref_ids ++ in_reply_to_ids) |> Enum.uniq() |> Enum.reject(&(&1 == message_id))
    existing_thread_id = find_existing_thread_id(search_ids)

    case existing_thread_id do
      nil ->
        new_thread_id = Ecto.UUID.generate()
        Logger.debug("Created new thread", metadata: [thread_id: new_thread_id])
        new_thread_id

      thread_id ->
        Logger.debug("Found existing thread", metadata: [thread_id: thread_id])
        thread_id
    end
  end

  defp extract_ids_from_header(header_string) when is_binary(header_string) do
    header_string
    |> String.split(~r/\s+/)
    |> Enum.map(&Headers.clean_id/1)
    |> Enum.reject(&UtilsFunctions.is_nil_or_blank/1)
  end

  defp extract_ids_from_header(_), do: []

  defp find_existing_thread_id([]), do: nil

  defp find_existing_thread_id(message_ids) when is_list(message_ids) do
    query =
      from(ei in Emails,
        where: ei.message_id in ^message_ids and not is_nil(ei.thread_id),
        select: ei.thread_id,
        limit: 1
      )

    Repo.one(query)
  end

  # HELPER FUNCTIONS

  @dialyzer {:no_match, send_raw_email: 5}
  @spec send_raw_email(
          binary(),
          binary(),
          list() | binary() | nil,
          list() | binary() | nil,
          list() | binary() | nil
        ) ::
          {:ok, term()} | {:error, term()}

  defp send_raw_email(raw_email, from, to_list, cc_list, bcc_list) do
    Logger.debug("Sending raw email to destinations",
      metadata: [destinations: [to_list, cc_list, bcc_list]]
    )

    Logger.debug("Sending raw email", metadata: [raw_email: raw_email])

    destinations =
      [to_list, cc_list, bcc_list]
      |> Enum.flat_map(&normalize_list/1)
      |> Enum.map(&to_string/1)
      |> Enum.reject(&UtilsFunctions.is_nil_or_blank/1)
      |> Enum.uniq()

    if destinations == [] do
      {:error, :no_valid_destinations}
    else
      Logger.debug("Sending email to destinations #{inspect(destinations)}")
      Logger.debug("Sending raw email #{inspect(raw_email)}")

      case ExAws.request(SES.send_raw_email(raw_email, source: from, destinations: destinations)) do
        {:ok, resp} -> {:ok, resp}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec normalize_list(nil | list() | binary()) :: list()
  defp normalize_list(nil), do: []

  defp normalize_list(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp normalize_list(value) when is_list(value), do: value

  defp normalize_list(_), do: []

  @spec create_email_imbox_record(map(), any(), binary()) ::
          {:ok, Spl.MailBox.Emails.t()} | {:error, term()}
  def create_email_imbox_record(params, user_id, thread_id) do
    params =
      Map.new(params, fn
        {k, v} when is_binary(k) -> {String.to_atom(k), v}
        pair -> pair
      end)

    html = Map.get(params, :html_body, "")
    text = Map.get(params, :text_body, "")

    preview = EmailComposer.generate_preview(text || html)

    Logger.debug("Show data params", metadata: [params: params])

    email_imbox_params = %{
      "user_id" => user_id,
      "to" => UtilsFunctions.list_to_string(params.to),
      "cc" => UtilsFunctions.list_to_string(params[:cc]),
      "bcc" => UtilsFunctions.list_to_string(params[:bcc]),
      "subject" => params.subject,
      "preview" => preview,
      "s3_url" => nil,
      "inbox_type" => @inbox_type.sent,
      "status" => @statuses.unread,
      "importance" => params[:importance] || "normal",
      "thread_id" => thread_id,
      "text_body" => text,
      "html_body" => html,
      "folder_id" => 2,
      "folder_type" => "SYSTEM"
    }

    MailBox.create_email(email_imbox_params)
  end

  defp generate_s3_key do
    :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)
  end

  defmodule UtilsFunctions do
    require Logger

    alias ExAws.S3

    def list_to_string(nil), do: nil
    def list_to_string([]), do: nil
    def list_to_string(value) when is_list(value), do: Enum.join(value, ",")
    def list_to_string(value), do: value

    def is_nil_or_blank(val) do
      is_nil(val) or (is_binary(val) and String.trim(val) == "")
    end

    def download_file_from_s3(bucket, key) do
      case S3.get_object(bucket, key) |> ExAws.request() do
        {:ok, %{body: body}} ->
          Logger.debug("Downloaded file from S3", metadata: [bucket: bucket, key: key])
          {:ok, body}

        {:error, reason} ->
          Logger.error("Error downloading from S3",
            metadata: [bucket: bucket, key: key, reason: inspect(reason)]
          )

          {:error, :download_failed}

        _ ->
          {:error, :unknown_s3_error}
      end
    end

    def upload_file_to_s3(bucket, key, body) do
      Logger.debug("Uploading file to S3",
        metadata: [bucket: bucket, key: key, size: byte_size(body)]
      )

      S3.put_object(bucket, key, body)
      |> ExAws.request()
      |> case do
        {:ok, _response} ->
          Logger.debug("File uploaded successfully to S3")
          {:ok, key}

        {:error, reason} ->
          Logger.error("Error uploading to S3", metadata: [reason: inspect(reason)])
          {:error, :upload_failed}
      end
    end

    def generate_references_value(original_references_str, new_clean_id) do
      existing_clean_refs =
        if is_nil_or_blank(original_references_str) do
          []
        else
          original_references_str
          |> String.split(~r/\s+/)
          |> Enum.map(&ParseMail.Headers.clean_id/1)
          |> Enum.reject(&is_nil_or_blank/1)
        end

      all_clean_refs =
        (existing_clean_refs ++ [new_clean_id])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      all_clean_refs
      |> Enum.map(fn id -> "<#{id}>" end)
      |> Enum.join(" ")
    end

    def generate_forward_subject(original_subject) do
      cond do
        String.starts_with?(original_subject, "Fwd: ") ->
          original_subject

        String.starts_with?(original_subject, "Re: ") ->
          "Fwd: " <> String.trim_leading(original_subject, "Re: ")

        true ->
          "Fwd: " <> original_subject
      end
    end

    def extract_email(from) do
      regex = ~r/<(.+?)>/

      case Regex.run(regex, from) do
        [_, email] -> email
        # fallback si ya viene solo
        _ -> from
      end
    end
  end

  defmodule EmailComposer do
    require Logger

    alias Mail.Encoders.QuotedPrintable
    alias Spl.ParseMail.Headers

    @spec compose_email(map(), binary()) :: {:ok, binary()} | {:error, term()}
    def compose_email(params, from) do
      IO.inspect(params, label: "params compose_email")
      IO.inspect(from, label: "from compose_email")

      try do
        raw_email = generate_raw_email_content(params, from)
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

        quoted_text =
          quote_original_text(original_email.text_body, original_email.from, current_date)

        reply_text_body_full = (params.text_body || "") <> quoted_text

        quoted_html =
          quote_original_html(original_email.html_body, original_email.from, current_date)

        reply_html_body_full =
          String.trim(params.html_body || "") <> String.trim(quoted_html)

        generated_message_id = "<#{generate_message_id(params.from)}>"
        original_message_id_clean = Headers.clean_id(original_email.message_id)

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

        forward_header_text = """
        \n\n-------- Forwarded Message --------
        From: #{original_email.from}
        Date: #{current_date}
        Subject: #{original_email.subject}
        To: #{Enum.join(original_email.to, ", ")}
        Cc: #{Enum.join(original_email.cc, ", ")}
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
        <b>To:</b> #{Enum.join(original_email.to, ", ")}<br>
        <b>Cc:</b> #{Enum.join(original_email.cc, ", ")}<br>
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

    defp generate_raw_email_content(email, from) do
      text_body = Map.get(email, :text_body, "")
      html_body = Map.get(email, :html_body, "")

      message_id = email[:message_id] || "<#{generate_message_id(from)}>"
      Logger.debug("message_id: #{message_id}")
      date = format_date(DateTime.utc_now())

      boundary = "----=_NextPart_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

      headers_map = build_email_headers(email, from, message_id, date, boundary)
      build_raw_email(headers_map, text_body, html_body)
    end

    defp build_email_headers(email, from, message_id, date, boundary) do
      priority_headers = build_priority_headers(email[:importance] || "normal")

      %{
        "Return-Path" => UtilsFunctions.extract_email(from),
        "From" => from,
        "To" => email.to,
        "Cc" => email[:cc],
        "Bcc" => email[:bcc],
        "Subject" => encode_header_if_needed(email.subject),
        "Date" => date,
        "X-Custom-Message-ID" => message_id,
        "MIME-Version" => "1.0",
        "Content-Type" => "multipart/alternative; boundary=\"#{boundary}\"",
        "X-Mailer" => "SPL Email System",
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
        "X-Custom-Message-ID" => message_id,
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
        "X-Custom-Message-ID" => message_id,
        "MIME-Version" => "1.0",
        "Content-Type" => "multipart/alternative; boundary=\"#{boundary}\"",
        "X-Mailer" => "SPL Email System",
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
      # Normalizamos desde el inicio:
      from = from || ""

      # Intentamos extraer email entre < > si existe
      email =
        case Regex.run(~r/<(.+?)>/, from, capture: :all_but_first) do
          [clean] ->
            clean

          _ ->
            # Si NO hay < >, buscamos directamente un correo válido
            case Regex.run(~r/[\w.+-]+@\w[\w.-]+\.\w+/, from) do
              [clean_email] -> clean_email
              # Fallback seguro
              _ -> "unknown@example.com"
            end
        end

      domain =
        email
        |> String.split("@")
        |> List.last()
        |> String.trim()

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
  end
end
