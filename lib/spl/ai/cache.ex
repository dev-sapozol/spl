defmodule Spl.AI.Cache do
  alias Spl.Cache

  @ttl 3600

  def get(key), do: Cache.get(key)

  def set(key, value), do: Cache.set(key, value, @ttl)

  def build_key(%{context: context, tone: tone}) do
    hash =
      :crypto.hash(:sha256, "#{context}:#{tone}")
      |> Base.encode16(case: :lower)

    "ai_draft:#{hash}"
  end
end
