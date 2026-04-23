defmodule Spl.AI.ProviderState do
  require Logger
  alias Spl.Redis

  @cooldown_seconds 60
  @prefix "ai_provider:exhausted:"

  def exhausted?(provider) do
    key = key(provider)
    case Redix.command(Redis, ["EXISTS", key]) do
      {:ok, 1} -> true
      _ -> false
    end
  end

  def mark_exhausted(provider) do
    key = key(provider)
    case Redix.command(Redis, ["SETEX", key, @cooldown_seconds, "1"]) do
      {:ok, "OK"} ->
        Logger.warning("Provider #{provider} marked exhausted for #{@cooldown_seconds}s")
      {:error, reason} ->
        Logger.error("Failed to mark provider exhausted: #{inspect(reason)}")
    end
  end

  def reset(provider) do
    Redix.command(Redis, ["DEL", key(provider)])
  end

  def status do
    providers = [:gemini, :openrouter_free, :openrouter_fallback, :openrouter_gemma]
    Enum.map(providers, fn p -> {p, exhausted?(p)} end)
  end

  defp key(provider), do: "#{@prefix}#{provider}"
end
