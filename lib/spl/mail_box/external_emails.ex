defmodule Spl.MailBox.ExternalEmails do
  use Ecto.Schema
  import Ecto.Changeset

  schema "external_emails" do
    field :email, :string
    field :status, :string, default: "pending"

    belongs_to :user, Spl.Account.User

    timestamps()
  end

  def changeset(external_email, attrs) do
    external_email
    |> cast(attrs, [:email, :status, :user_id])
    |> validate_required([:email, :user_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> unique_constraint(:email)
  end
end
