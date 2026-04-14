defmodule Spl.MailBox.Emails do
  use Ecto.Schema
  import Ecto.Changeset
  alias Spl.Account.User

  @type t :: %__MODULE__{}

  schema "emails" do
    belongs_to :user, User
    field :original_message_id, :string
    field :thread_id, :string
    field :in_reply_to, :string
    field :references, {:array, :string}
    # Estructura: [%{name: "Nombre", email: "correo@dominio.com"}]
    field :to_addresses, {:array, :map}
    field :cc_addresses, {:array, :map}
    field :sender_email, :string
    field :sender_name, :string
    field :subject, :string
    field :preview, :string
    field :is_read, :boolean, default: false
    field :has_attachment, :boolean, default: false
    field :importance, :integer, default: 0
    field :body_size_bytes, :integer
    field :attachments_size_bytes, :integer
    field :body_raw_storage_key, :string # El .eml original
    field :body_storage_key, :string     # El JSON {html, text} procesado
    field :folder_type, Ecto.Enum, values: [:SYSTEM, :USER]
    field :folder_id, :integer
    field :deleted_at, :utc_datetime
    timestamps()
  end

  def changeset(emails, attrs) do
    emails
    |> cast(attrs, [
      :user_id,
      :original_message_id,
      :thread_id,
      :in_reply_to,
      :references,
      :to_addresses,
      :cc_addresses,
      :sender_email,
      :sender_name,
      :subject,
      :preview,
      :is_read,
      :has_attachment,
      :importance,
      :body_size_bytes,
      :attachments_size_bytes,
      :body_raw_storage_key,
      :body_storage_key,
      :folder_type,
      :folder_id,
      :deleted_at
    ])
    |> validate_required([
      :user_id,
      :folder_id,
      :folder_type
    ])
  end
end
