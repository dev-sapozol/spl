defmodule SplWeb.Schema.Emails do
  use Absinthe.Schema.Notation
  alias SplWeb.Schema.Middleware

  enum :folder_type_enum do
    value(:SYSTEM)
    value(:USER)
  end

  # === TYPE ===
  object :emails do
    field :id, :id
    field :user_id, :id
    field :to, :string
    field :sender_name, :string
    field :sender_email, :string

    field :subject, :string
    field :preview, :string
    field :text_body, :string
    field :html_body, :string

    field :original_message_id, :string
    field :cc, :string
    field :inbox_type, :integer
    field :is_read, :boolean
    field :has_attachment, :boolean
    field :importance, :integer
    field :in_reply_to, :string
    field :references, :string
    field :s3_url, :string
    field :thread_id, :string
    field :folder_type, :folder_type_enum
    field :folder_id, :integer
    field :deleted_at, :string
    field :inserted_at, :string
    field :updated_at, :string
  end

  input_object :email_filter do
    field :user_id, :id
    field :to, :string
    field :sender_email, :string
    field :subject, :string

    field :is_read, :boolean
    field :importance, :integer
    field :has_attachment, :boolean
    field :deleted_at, :string
    field :folder_type, :folder_type_enum
    field :folder_id, :integer
  end

  object :list_basic_email do
    field :id, :id
    field :subject, :string
    field :preview, :string
    field :sender_name, :string
    field :sender_email, :string
    field :to, :string

    field :is_read, :boolean
    field :has_attachment, :boolean
    field :importance, :integer
    field :deleted_at, :string
    field :folder_type, :string
    field :folder_id, :integer
    field :inserted_at, :string
  end

  input_object :send_email do
    field :to, :string
    field :cc, :string
    field :bcc, :string
    field :subject, :string
    field :text_body, :string
    field :html_body, :string

    field :has_attachment, :boolean
    field :importance, :integer
    field :folder_id, :integer
  end

  input_object :reply_email do
    field :parent_id, non_null(:id)
    field :text_body, :string
    field :html_body, :string
    field :reply_all, :boolean, default_value: false
    field :subject, :string
    field :has_attachment, :boolean
  end

  object :folder_info do
    field :id, :id
    field :name, :string
    field :folder_type, :folder_type_enum
    field :total, :integer
    field :unread, :integer
  end

  object :folder_emails do
    field :folder_id, :integer
    field :folder_type, :folder_type_enum
    field :emails, list_of(:list_basic_email)
  end

  object :preload_mailbox do
    field :system_folders, list_of(:folder_info)
    field :user_folders, list_of(:folder_info)
    field :emails_by_folder, list_of(:folder_emails)
  end

  # === QUERIES ===

  object :email_queries do
    field :get_email, type: :emails do
      arg(:id, non_null(:id))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailsResolver.get/2)
    end

    field :list_emails, list_of(:list_basic_email) do
      arg(:filter, non_null(:email_filter))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailsResolver.list/2)
    end

    field :preload_mailbox, type: :preload_mailbox do
      arg(:user_id, non_null(:integer_id))
      arg(:limit, :integer, default_value: 50)
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailsResolver.preload_mailbox/2)
    end
  end

  # === MUTATIONS ===

  object :email_mutations do
    field :send_email, type: :emails do
      arg(:input, non_null(:send_email))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailsResolver.create/2)
    end

    field :reply_email, type: :emails do
      arg(:input, non_null(:reply_email))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailsResolver.reply/2)
    end

    field :delete_email, type: :emails do
      arg(:id, non_null(:id))
      middleware(Middleware.Authenticate, :all)
      resolve(&Spl.EmailsResolver.delete/2)
    end
  end
end
