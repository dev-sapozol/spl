defmodule Spl.InboxEmail do
  import Ecto.Query
  use GenServer
  require Logger

  alias Spl.Account
  alias Spl.MailBox.Emails
  alias ExAws.{SES, SQS, S3}
  alias Spl.{AwsBuilder, Repo, MailBox, ParseMail, Account, EmailComposer, EmailStorage}
  alias Spl.ParseMail.{Email, Headers}
  alias Spl.InboxEmail.UtilsFunctions

  @inbox_type %{received: 0, sent: 1, draft: 2}
  @statuses %{unread: 0, sent: 1, failed: 99}
  @region "us-east-1"

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    listener_messages_sqs()
    {:ok, %{}}
  end

  def listener_messages_sqs() do
    Logger.info("processing genserver")
    Process.send_after(self(), :process_messages, 715_000)
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
      where: ei.sender_email == ^email,
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

  def register_email(raw_eml_body, _s3_url, _message_id_from_header) do
    case ParseMail.parse_email_content(raw_eml_body) do
      {:ok, %Email{} = parsed_email} ->
        Logger.info("Successfully parsed received email")
        thread_id = find_or_create_thread_id(parsed_email)

        create_received_email_record(raw_eml_body, parsed_email, thread_id)

      {:error, _type, reason} ->
        Logger.error("Error parsing email: #{inspect(reason)}")
        {:error, :parse_failed}
    end
  end

  defp create_received_email_record(raw_eml_body, parsed_email, thread_id) do
    target_email =
      case parsed_email.to do
        list when is_list(list) -> List.first(list)
        str when is_binary(str) -> str
        _ -> nil
      end

    user_id = Account.get_user_id_by_email(target_email)

    Logger.debug("From: #{inspect(parsed_email.from)}")

    {sender_name, sender_email} = UtilsFunctions.parse_address(parsed_email.from)

    Logger.debug("Sender name: #{inspect(sender_name)}")
    Logger.debug("Sender email: #{inspect(sender_email)}")

    with {:ok, raw_key} <- EmailStorage.upload_raw_email(raw_eml_body, user_id),
         {:ok, body_key, body_size} <-
           EmailStorage.upload_html_body(
             parsed_email.html_body,
             user_id
           ) do
      attachments_size = EmailStorage.calculate_attachments_size(parsed_email.attachments)

      received_email_attrs = %{
        user_id: user_id,
        sender_name: sender_name,
        sender_email: sender_email,
        to_addresses: parse_addresses_to_array(parsed_email.to),
        cc_addresses: parse_addresses_to_array(parsed_email.cc),
        subject: parsed_email.subject,
        preview: EmailComposer.generate_preview(parsed_email.html_body),
        body_raw_storage_key: raw_key,
        body_storage_key: body_key,
        body_size_bytes: body_size,
        attachments_size_bytes: attachments_size,
        has_attachment: not Enum.empty?(parsed_email.attachments),
        importance: extract_importance(parsed_email),
        original_message_id: parsed_email.message_id,
        in_reply_to: UtilsFunctions.list_to_string(parsed_email.in_reply_to),
        references: parsed_email.references || [],
        thread_id: thread_id,
        is_read: false,
        folder_id: 1,
        folder_type: :SYSTEM
      }

      case MailBox.create_email(received_email_attrs) do
        {:ok, new_email} ->
          Logger.info("Successfully registered received email",
            metadata: [email_id: new_email.id]
          )

          {:ok, new_email}

        {:error, reason} ->
          Logger.error("Error registering received email: #{inspect(reason)}")
          EmailStorage.delete_from_r2(raw_key)
          EmailStorage.delete_from_r2(body_key)
          {:error, :registration_failed}
      end
    else
      {:error, reason} ->
        Logger.error("Error uploading to R2: #{inspect(reason)}")
        {:error, :storage_upload_failed}
    end
  end

  # Helper to parse email addresses to array of maps
  defp parse_addresses_to_array(addresses) when is_list(addresses) do
    Enum.map(addresses, fn addr ->
      case UtilsFunctions.parse_address(addr) do
        {name, email} -> %{name: name, email: email}
        _ -> %{name: "", email: addr}
      end
    end)
  end

  defp parse_addresses_to_array(address) when is_binary(address) do
    case UtilsFunctions.parse_address(address) do
      {name, email} -> [%{name: name, email: email}]
      _ -> [%{name: "", email: address}]
    end
  end

  defp parse_addresses_to_array(_), do: []

  defp extract_importance(parsed_email) do
    case parsed_email.importance do
      "high" -> 2
      "low" -> 1
      _ -> 0
    end
  end

  # EMAIL SENDING

  @dialyzer {:no_match, send_email: 1}

  @spec send_email(map()) ::
          {:ok, Spl.MailBox.Emails.t()} | {:error, term()}

  def send_email(params) do
    Logger.debug("Processing email send", metadata: [to: params[:to]])

    sender_email = params[:sender_email]
    sender_name = params[:sender_name]

    from_string =
      cond do
        sender_name && sender_email -> "#{sender_name} <#{sender_email}>"
        sender_email -> sender_email
        true -> "unknown@spl-system.com"
      end

    thread_id = Ecto.UUID.generate()
    user_id = params[:user_id]
    Logger.info("Sending email", metadata: [thread_id: thread_id, user_id: user_id])

    with {:ok, raw_email} <- EmailComposer.compose_email(params),
         {:ok, raw_key} <- EmailStorage.upload_raw_email(raw_email, user_id),
         {:ok, body_key, body_size} <-
           EmailStorage.upload_html_body(
             params[:html_body],
             user_id
           ),
         {:ok, _ses_response} <-
           send_raw_email(raw_email, params[:to], params[:cc], params[:bcc], from_string),
         {:ok, email_record} <-
           create_email_record_sent(params, thread_id, raw_key, body_key, body_size) do
      {:ok, email_record}
    else
      {:error, reason} ->
        Logger.error("Error sending email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_email_record_sent(params, thread_id, raw_key, body_key, body_size) do
    user_id = params[:user_id]
    attachments_size = EmailStorage.calculate_attachments_size(params[:attachments] || [])

    email_attrs = %{
      user_id: user_id,
      sender_email: params[:sender_email],
      sender_name: params[:sender_name],
      to_addresses: parse_addresses_to_array(params[:to]),
      cc_addresses: parse_addresses_to_array(params[:cc]),
      subject: params[:subject],
      preview: EmailComposer.generate_preview(params[:html_body]),
      body_raw_storage_key: raw_key,
      body_storage_key: body_key,
      body_size_bytes: body_size,
      attachments_size_bytes: attachments_size,
      has_attachment: (params[:attachments] || []) |> Enum.empty?() |> Kernel.not(),
      importance: params[:importance] || 0,
      original_message_id: Ecto.UUID.generate(),
      thread_id: thread_id,
      is_read: false,
      folder_id: 2,
      folder_type: :SYSTEM
    }

    MailBox.create_email(email_attrs)
  end

  # EMAIL REPLY

  def send_reply(input, original_email, current_user) do
    Logger.debug("Processing reply for email ID: #{original_email.id}")
    {to_list, cc_list} = calculate_reply_recipients(original_email, current_user, input.reply_all)

    user_id = current_user.id

    params = %{
      from: "#{current_user.name} <#{current_user.email}>",
      to: to_list,
      cc: cc_list,
      bcc: [],
      subject: input.subject,
      html_body: input.html_body,
      importance: original_email.importance || 0
    }

    thread_id = original_email.thread_id

    with {:ok, composition} <- EmailComposer.compose_reply(params, original_email),
         raw_mime_string = composition.raw_content,
         generated_headers = composition.headers,
         {:ok, raw_key} <- EmailStorage.upload_raw_email(raw_mime_string, user_id),
         {:ok, body_key, body_size} <-
           EmailStorage.upload_html_body(
             input.html_body,
             user_id
           ),
         {:ok, _ses_response} <-
           send_raw_email(raw_mime_string, params[:to], params[:cc], params[:bcc], params[:from]),
         {:ok, sent_email} <-
           create_reply_db_record(
             input,
             params,
             generated_headers,
             original_email,
             current_user,
             thread_id,
             raw_key,
             body_key,
             body_size
           ) do
      {:ok, sent_email}
    else
      error ->
        Logger.error("Failed to reply: #{inspect(error)}")
        error
    end
  end

  def create_reply_db_record(
        input,
        params,
        headers,
        _original_email,
        current_user,
        thread_id,
        raw_key,
        body_key,
        body_size
      ) do
    message_id = headers["Message-Id"]
    in_reply_to = headers["In-Reply-To"]
    references = headers["References"]

    reply_attrs = %{
      user_id: current_user.id,
      sender_email: current_user.email,
      sender_name: current_user.name,
      to_addresses: parse_addresses_to_array(params[:to]),
      cc_addresses: parse_addresses_to_array(params[:cc]),
      subject: params[:subject],
      preview: EmailComposer.generate_preview(params[:html_body]),
      body_raw_storage_key: raw_key,
      body_storage_key: body_key,
      body_size_bytes: body_size,
      attachments_size_bytes: EmailStorage.calculate_attachments_size(input[:attachments] || []),
      has_attachment: not Enum.empty?(input[:attachments] || []),
      thread_id: thread_id,
      original_message_id: message_id,
      in_reply_to: in_reply_to,
      references: parse_references(references),
      is_read: false,
      folder_type: :SYSTEM,
      folder_id: 2,
      importance: params[:importance] || 0
    }

    Logger.debug("Saving reply to DB", metadata: [email_id: current_user.id])
    MailBox.create_email(reply_attrs)
  end

  defp parse_references(ref_string) when is_binary(ref_string) do
    ref_string
    |> String.split(~r/\s+/)
    |> Enum.reject(&UtilsFunctions.is_nil_or_blank/1)
  end

  def calculate_reply_recipients(original, me, reply_all) do
    primary_to = [original.sender_email]

    if reply_all do
      original_tos = normalize_list(original.to)
      original_ccs = normalize_list(original.cc)

      all_involved = original_tos ++ original_ccs

      others =
        all_involved
        |> Enum.reject(fn email -> email == me.email or email == original.sender_email end)
        |> Enum.uniq()

      {primary_to, others}
    else
      {primary_to, []}
    end
  end

  # THREAD MANAGEMENT

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

  # HELPER FUNCTIONS

  @dialyzer {:no_match, send_raw_email: 4}
  @spec send_raw_email(
          binary(),
          list() | binary() | nil,
          list() | binary() | nil,
          list() | binary() | nil,
          binary()
        ) ::
          {:ok, term()} | {:error, term()}

  defp send_raw_email(raw_email, from_string, to_list, cc_list, bcc_list) do
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

      case ExAws.request(
             SES.send_raw_email(raw_email, source: from_string, destinations: destinations)
           ) do
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

  @spec create_email_imbox_record(map(), binary()) ::
          {:ok, Spl.MailBox.Emails.t()} | {:error, term()}
  def create_email_imbox_record(params, thread_id) do
    Logger.debug("Creating email imbox record: #{inspect(params)}")
    Logger.debug("Thread id", metadata: [thread_id: thread_id])

    html = Map.get(params, :html_body, "")

    preview = EmailComposer.generate_preview(html)

    email_imbox_params = %{
      user_id: params.user_id,
      sender_name: params.sender_name,
      sender_email: params.sender_email,
      to: UtilsFunctions.list_to_string(params.to),
      cc: UtilsFunctions.list_to_string(params[:cc]),
      bcc: UtilsFunctions.list_to_string(params[:bcc]),
      subject: params.subject,
      preview: preview,
      s3_url: nil,
      inbox_type: @inbox_type.sent,
      status: @statuses.unread,
      importance: params[:importance] || "normal",
      thread_id: thread_id,
      html_body: html,
      folder_id: 2,
      folder_type: "SYSTEM"
    }

    MailBox.create_email(email_imbox_params)
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
        _ -> from
      end
    end

    def parse_address(raw_string) when is_binary(raw_string) do
      case Regex.run(~r/(?:"?([^"]*)"?\s)?(?:<?(.+@[^>]+)>?)/, raw_string) do
        [_, name, email] ->
          clean_name = if name == "", do: extract_user_from_email(email), else: String.trim(name)
          {clean_name, String.trim(email)}

        _ ->
          # Fallback
          {raw_string, raw_string}
      end
    end

    def parse_address(list) when is_list(list), do: parse_address(List.first(list))
    def parse_address(_), do: {"Unknown", "unknown"}

    defp extract_user_from_email(email) do
      email |> String.split("@") |> List.first() |> String.capitalize()
    end
  end
end
