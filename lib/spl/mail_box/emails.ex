defmodule Spl.MailBox.Emails do
  use Ecto.Schema
  import Ecto.Changeset
  alias Spl.Account.User

  @type t :: %__MODULE__{}

  schema "emails" do
    belongs_to :user, User
    field :original_message_id, :string
    field :to, :string
    field :cc, :string
    field :subject, :string
    field :preview, :string
    field :inbox_type, :integer
    field :is_read, :boolean
    field :has_attachment, :boolean
    field :importance, :integer
    field :in_reply_to, :string
    field :references, :string
    field :text_body, :string
    field :html_body, :string
    field :s3_url, :string
    field :thread_id, :string
    field :deleted_at, :string
    field :folder_type, Ecto.Enum, values: [:SYSTEM, :USER]
    field :folder_id, :integer
    field :sender_email, :string
    field :sender_name, :string

    timestamps()
  end

  def changeset(emails, attrs) do

    emails
    |> cast(attrs, [
      :user_id,
      :original_message_id,
      :to,
      :cc,
      :subject,
      :preview,
      :inbox_type,
      :is_read,
      :has_attachment,
      :importance,
      :in_reply_to,
      :references,
      :text_body,
      :html_body,
      :s3_url,
      :thread_id,
      :deleted_at,
      :folder_type,
      :folder_id,
      :sender_email,
      :sender_name
    ])
    |> validate_required([
      :user_id,
      :to,
      :folder_id,
      :folder_type
    ])
  end
end
