defmodule Spl.SignatureV4SES do
  import SweetXml
  require Logger

  @region "us-east-1"
  @service "ses"
  @host "email.us-east-1.amazonaws.com"
  @endpoint "https://#{@host}"
  @content_type "application/x-www-form-urlencoded"
  @aws_version "2010-12-01"

  def aws_access_key do
    key = Application.get_env(:spl, :aws)[:aws_access_key]
    key
  end

  def aws_secret_key do
    key = Application.get_env(:spl, :aws)[:aws_secret_key]
    key
  end

  def verify_email_identity(email) do
    request(
      "VerifyEmailIdentity",
      %{"EmailAddress" => email},
      fn _ -> :ok end
    )
  end

  def get_email_verification_status(email) do
    request(
      "GetIdentityVerificationAttributes",
      %{"Identities.member.1" => email},
      &parse_email_status(&1, email)
    )
  end

  defp request(action, extra_params, parser) do
    body =
      URI.encode_query(
        Map.merge(
          %{
            "Action" => action,
            "Version" => @aws_version
          },
          extra_params
        )
      )

    now = Timex.now("UTC")
    timestamp = Timex.format!(now, "{YYYY}{0M}{0D}T{h24}{m}{s}Z")
    date = String.slice(timestamp, 0..7)

    with {:ok, response} <-
           HTTPoison.post(@endpoint, body, build_headers(body, timestamp, date), []) do
      handle_response(response, parser)
    else
      error ->
        Logger.error("SES request failed: #{inspect(error)}")
        {:error, "SES request failed"}
    end
  end

  defp handle_response(%{status_code: 200, body: body}, parser) do
    {:ok, parser.(body)}
  rescue
    _ -> {:error, "Parsing failed"}
  end

  defp handle_response(%{status_code: status, body: body}, _) do
    # <--- AGREGA ESTO PARA VER EL XML DE ERROR
    Logger.error("SES Error Body: #{body}")
    {:error, "SES error #{status}"}
  end

  defp build_headers(body, timestamp, date) do
    body_hash = hash(body)
    canonical = canonical_request(body_hash, timestamp)
    string_to_sign = string_to_sign(canonical, timestamp, date)
    signature = sign(string_to_sign, signing_key(date))
    credential = "#{aws_access_key()}/#{date}/#{@region}/#{@service}/aws4_request"

    [
      {"Content-Type", @content_type},
      {"Host", @host},
      {"X-Amz-Date", timestamp},
      {"Authorization",
       "AWS4-HMAC-SHA256 Credential=#{credential}, SignedHeaders=content-type;host;x-amz-date, Signature=#{signature}"}
    ]
  end

  defp canonical_request(body_hash, timestamp) do
    "POST\n/\n\ncontent-type:#{@content_type}\nhost:#{@host}\nx-amz-date:#{timestamp}\n\ncontent-type;host;x-amz-date\n#{body_hash}"
  end

  defp string_to_sign(canonical, timestamp, date) do
    "AWS4-HMAC-SHA256\n#{timestamp}\n#{date}/#{@region}/#{@service}/aws4_request\n#{hash(canonical)}"
  end

  defp signing_key(date) do
    "AWS4#{aws_secret_key()}"
    |> hmac(date)
    |> hmac(@region)
    |> hmac(@service)
    |> hmac("aws4_request")
  end

  defp hash(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  defp hmac(key, msg), do: :crypto.mac(:hmac, :sha256, key, msg)
  defp sign(msg, key), do: hmac(key, msg) |> Base.encode16(case: :lower)

  defp parse_email_status(body, email) do
    xpath(
      body,
      ~x"//entry[key/text()='#{email}']/value/VerificationStatus/text()"s
    )
  end

  def send_email(%{to: to, subject: subject, html_body: html_body, text_body: text_body}) do
    request(
      "SendEmail",
      %{
        "Source" => "no-reply@esanpol.xyz",
        "Destination.ToAddresses.member.1" => to,
        "Message.Subject.Data" => subject,
        "Message.Subject.Charset" => "UTF-8",
        "Message.Body.Html.Data" => html_body,
        "Message.Body.Html.Charset" => "UTF-8",
        "Message.Body.Text.Data" => text_body,
        "Message.Body.Text.Charset" => "UTF-8"
      },
      fn response ->
        IO.inspect(response, label: "SES RESPONSE")
        {:ok, response}
      end
    )
  end
end
