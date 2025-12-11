defmodule SplWeb.Schema.Scalars do
  use Absinthe.Schema.Notation

  # Scalar para IDs enteros
  scalar :integer_id do
    parse(&parse_integer_id/1)
    serialize(& &1)
  end

  defp parse_integer_id(%Absinthe.Blueprint.Input.Integer{value: v}), do: {:ok, v}

  defp parse_integer_id(%Absinthe.Blueprint.Input.String{value: v}) do
    case Integer.parse(v) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_integer_id(_), do: :error
end
