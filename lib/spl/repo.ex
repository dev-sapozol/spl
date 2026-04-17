defmodule Spl.Repo do
  use Ecto.Repo,
    otp_app: :spl,
    adapter: Ecto.Adapters.Postgres
end
