defmodule SplWeb.Schema.Middleware.ChangesetErrors do
  @behaviour Absinthe.Middleware

  def call(%{errors: [ %Ecto.Changeset{} = changeset ]} = resolution, _config) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    Absinthe.Resolution.put_result(resolution, {:error, errors})
  end

  def call(resolution, _config), do: resolution
end
