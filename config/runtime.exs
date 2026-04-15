import Config
import Dotenvy

if config_env() == :dev do
  Dotenvy.source!([Path.expand("../.env", __DIR__)])
  |> Enum.each(fn {k, v} -> System.put_env(k, v) end)
end

# =========================
# ENV VARS
# =========================

secret_key_jwk =
  System.get_env("SECRET_KEY_JWK") || raise "SECRET_KEY_JWK missing"

redis_url = System.get_env("REDIS_URL")

# =========================
# GUARDIAN
# =========================

config :spl, Spl.Auth.Guardian,
  issuer: "spl",
  secret_key: secret_key_jwk,
  token_ttl: %{
    access: {30, :minutes},
    refresh: {30, :days}
  }

# =========================
# R2 (Cloudflare)
# =========================

config :spl, :r2,
  access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("R2_SECRET_KEY"),
  account_id: System.get_env("R2_ACCOUNT_ID"),
  bucket_name: System.get_env("R2_BUCKET_NAME")

# =========================
# REDIS
# =========================

config :spl, :redis, url: redis_url

# =========================
# AWS
# =========================

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_KEY")

config :spl, :aws,
  aws_access_key: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret_key: System.get_env("AWS_SECRET_KEY")

# =========================
# DATABASE (MYSQL)
# =========================

config :spl, Spl.Repo,
  adapter: Ecto.Adapters.MyXQL,
  username: System.get_env("DB_USERNAME") || raise("DB_USERNAME missing"),
  password: System.get_env("DB_PASSWORD") || raise("DB_PASSWORD missing"),
  database: System.get_env("DB_NAME") || raise("DB_NAME missing"),
  hostname: System.get_env("DB_HOSTNAME") || raise("DB_HOSTNAME missing"),
  port: String.to_integer(System.get_env("DB_PORT") || "3306"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  connect_opts: [tcp: true, allowPublicKeyRetrieval: true, ssl: false]

# =========================
# PHOENIX SERVER (RENDER)
# =========================

config :spl, SplWeb.Endpoint,
  server: true,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")]

# =========================
# PROD CONFIG
# =========================

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE missing"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :spl, SplWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :spl, :cors_origins,
  System.get_env("ALLOWED_ORIGINS", "")
  |> String.split(",", trim: true)
  |> Enum.reject(&(&1 == ""))
end
