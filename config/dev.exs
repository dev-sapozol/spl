import Config

# =========================
# ENDPOINT
# =========================
config :spl, SplWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "spl_58@&h84#mb28xjBNABbG945*4%0",
  watchers: [],
  server: true


config :spl, :cors_origins, ["http://localhost:5173", "http://localhost:4000"]

# =========================
# DEV ROUTES
# =========================
config :spl, dev_routes: true

# =========================
# LOGGER
# =========================
config :logger, level: :debug
config :logger, backends: [:console]

config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:request_id, :module, :function]

# =========================
# PHOENIX
# =========================
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

# =========================
# SWOOSH
# =========================
config :swoosh, :api_client, false
