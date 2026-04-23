defmodule Spl.AI.EmailDraftRouter do
  require Logger
  alias Spl.AI.{Cache, ProviderState, Providers}

  @providers [:gemini, :openrouter_free, :openrouter_fallback, :openrouter_gemma]

  @spec generate_draft(map()) :: {:ok, map()} | {:error, term()}
  def generate_draft(params) do
    Logger.info("generate_draft called with context: #{inspect(params.context)}")

    case validate_email_scope(params.context) do
      :ok ->
        cache_key = Cache.build_key(params)

        case Cache.get(cache_key) do
          {:ok, cached} ->
            Logger.info("AI draft served from cache")
            {:ok, Map.put(cached, :from_cache, true)}

          :error ->
            result = try_providers(params)

            if match?({:ok, _}, result) do
              {:ok, draft} = result
              Cache.set(cache_key, draft)
            end

            result
        end

      {:error, :out_of_scope} ->
        Logger.info("AI draft request out of scope")
        {:error, :out_of_scope}
    end
  end

  defp try_providers(params) do
    available = Enum.reject(@providers, &ProviderState.exhausted?/1)
    Logger.info("Available providers: #{inspect(available)}")

    if available == [] do
      Logger.error("All providers exhausted, no fallback available")
      {:error, :all_providers_failed}
    else
      Enum.reduce_while(available, {:error, :all_providers_failed}, fn provider, _acc ->
        case Providers.call(provider, params) do
          {:ok, result} ->
            {:halt, {:ok, result}}

          {:error, :rate_limited} ->
            ProviderState.mark_exhausted(provider)
            Logger.warning("Rate limited #{provider}")
            {:cont, {:error, :all_providers_failed}}

          {:error, {:http_error, 404}} ->
            Logger.error("Provider #{provider} model not found")
            {:cont, {:error, :all_providers_failed}}

          {:error, :timeout} ->
            Logger.warning("Timeout #{provider}, retrying next")
            {:cont, {:error, :all_providers_failed}}

          {:error, reason} ->
            Logger.error("Provider #{provider} failed: #{inspect(reason)}")
            {:cont, {:error, :all_providers_failed}}
        end
      end)
    end
  end

  defp validate_email_scope(context) when is_binary(context) do
    normalized = normalize_text(context)

    out_of_scope_keywords = [
      "codigo",
      "code",
      "programa",
      "sql",
      "database",
      "base de datos",
      "chiste",
      "joke",
      "receta",
      "recipe",
      "clima",
      "weather",
      "matematicas",
      "math",
      "historia",
      "history"
    ]

    is_out_of_scope =
      Enum.any?(out_of_scope_keywords, fn keyword ->
        String.contains?(normalized, normalize_text(keyword))
      end)

    # También rechazar si el contexto es demasiado corto para ser útil
    too_short = String.length(String.trim(context)) < 3

    if is_out_of_scope or too_short do
      {:error, :out_of_scope}
    else
      :ok
    end
  end

  defp validate_email_scope(_), do: {:error, :invalid_context}

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
