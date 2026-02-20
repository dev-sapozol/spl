defmodule Spl.Cache do
  require Logger
  alias Spl.Redis

  def get(key) do
    case Redix.command(Redis, ["GET", key]) do
      {:ok, nil} ->
        :error

      {:ok, value} when is_binary(value) ->
        case Jason.decode(value, keys: :atoms) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, _} ->
            :error
        end

      {:error, reason} ->
        Logger.error("Cache GET failed", metadata: [key: key, reason: inspect(reason)])
        :error
    end
  end

  def set(key, value, ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0 do
    case Jason.encode(value) do
      {:ok, encoded} ->
        case Redix.command(Redis, ["SETEX", key, ttl_seconds, encoded]) do
          {:ok, "OK"} ->
            :ok

          {:error, reason} ->
            Logger.error("Cache SET failed", metadata: [key: key, reason: inspect(reason)])
            Logger.error("REASON: #{inspect(reason)}")
            :error
        end

      {:error, reason} ->
        Logger.error("Cache serialization failed", metadata: [key: key, reason: inspect(reason)])
        :error
    end
  end

  def del(key) do
    case Redix.command(Redis, ["DEL", key]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache DEL failed", metadata: [key: key, reason: inspect(reason)])
        :error
    end
  end

  def del_many(keys) when is_list(keys) do
    case Redix.command(Redis, ["DEL" | keys]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache DEL_MANY failed", metadata: [keys: keys, reason: inspect(reason)])
        :error
    end
  end
end
