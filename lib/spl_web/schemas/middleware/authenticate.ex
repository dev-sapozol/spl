defmodule SplWeb.Schema.Middleware.Authenticate do
  @behaviour Absinthe.Middleware
  @impl true

  def call(res, _term) do
    case res.context do
      %{current_user: user} when not is_nil(user) ->
        res
      _ ->
        Absinthe.Resolution.put_result(res, {:error, "Unauthorized"})
        |> put_http_status(401)
    end
  end

  defp put_http_status(res, status) do
    %{res | context: Map.put(res.context, :http_status, status)}
  end
end
