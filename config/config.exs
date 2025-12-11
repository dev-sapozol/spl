import Config

config :spl,
  ecto_repos: [Spl.Repo],
  generators: [timestamp_type: :utc_datetime]

config :spl, :jwk,
  secret_key_jwk: System.get_env("SECRET_KEY_JWK")

config :spl, SplWeb.Auth.Guardian,
  issuer: "triggerflow",
  secret_key: "secret_key_jwk" # Cambiar a otra secret key

# Configures the endpoint
config :spl, SplWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SplWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Spl.PubSub,
  live_view: [signing_salt: "TCraAcVs"]

config :spl, Spl.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
