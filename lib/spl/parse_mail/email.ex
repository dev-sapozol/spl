defmodule Spl.ParseMail.Email do
  alias Spl.ParseMail

  defstruct [
    :from,
    :to,
    :cc,
    :bcc,
    :reply_to,
    :sender,
    :subject,
    :message_id,
    :references,
    :in_reply_to,
    :date,
    :priority,
    :importance,
    :read_receipt,
    :content_type,
    :content_transfer_encoding,
    :text_body,
    :html_body,
    :attachments,
    :custom_headers,
    :raw_headers,
    :raw_content
  ]

  @type t :: %__MODULE__{
          from: String.t() | nil,
          to: [String.t()],
          cc: [String.t()],
          bcc: [String.t()],
          reply_to: [String.t()],
          sender: String.t() | nil,
          subject: String.t(),
          message_id: String.t() | nil,
          references: [String.t()],
          in_reply_to: String.t() | nil,
          date: DateTime.t() | nil,
          priority: String.t() | nil,
          importance: String.t() | nil,
          read_receipt: String.t() | nil,
          content_type: String.t(),
          content_transfer_encoding: String.t(),

          # FIX: Estos pueden ser nil
          text_body: String.t() | nil,
          html_body: String.t() | nil,
          attachments: [ParseMail.Attachment.t()],
          custom_headers: map(),
          raw_headers: map(),
          raw_content: String.t()
        }
end
