import Config

config :spl,
  ecto_repos: [Spl.Repo],
  generators: [timestamp_type: :utc_datetime]

# Endpoint base
config :spl, SplWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SplWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Spl.PubSub,
  live_view: [signing_salt: "TCraAcVs"]

# Mailer (dev)
config :spl, Spl.Mailer,
  adapter: Swoosh.Adapters.Local

# Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# JSON
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
