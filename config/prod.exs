import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :debug

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

config :spl, SplWeb.Endpoint,
  check_origin: [
    "https://www.esanpol.xyz",
    "https://esanpol.xyz"
  ]
