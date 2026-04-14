defmodule SplWeb.Plugs.GraphqlMultipart do
  @behaviour Plug
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    # Unificamos params
    params = Map.merge(conn.params, conn.body_params)

    with %{"operations" => ops, "map" => map} <- params,
         true <- is_binary(ops),
         true <- is_binary(map) do

      # 1. Decodificar JSONs
      ops_decoded = Jason.decode!(ops)
      map_decoded = Jason.decode!(map)

      # 2. Inyectar el archivo %Plug.Upload{} dentro de las variables
      ops_with_files = map_files_to_operations(ops_decoded, map_decoded, params)

      # 3. "Aplanar": Ponemos 'query' y 'variables' en la raíz de params
      # Esto engaña a Absinthe para que crea que es una petición estándar
      new_params = Map.merge(conn.params, ops_with_files)

      # Actualizamos tanto params como body_params por seguridad
      conn
      |> Map.put(:params, new_params)
      |> Map.put(:body_params, new_params)
    else
      _ -> conn
    end
  rescue
    e ->
      Logger.error(">>> [DEBUG PLUG] Error: #{inspect(e)}")
      conn
  end

defp map_files_to_operations(operations, map_decoded, params) do
    Enum.reduce(map_decoded, operations, fn {key, paths}, acc ->
      case params[key] do
        %Plug.Upload{} = upload ->

          # CAMBIO: Creamos un mapa con llaves STRING manualmente.
          # Esto evita conflictos de tipos en Absinthe.
          upload_map = %{
            "path" => upload.path,
            "filename" => upload.filename,
            "content_type" => upload.content_type
          }

          Enum.reduce(paths, acc, fn path, ops_acc ->
            set_nested_value(ops_acc, String.split(path, "."), upload_map)
          end)

        _ ->
          acc
      end
    end)
  end

  defp set_nested_value(map, [key], value) do
    Map.put(map, key, value)
  end

  defp set_nested_value(map, [key | rest], value) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, set_nested_value(nested, rest, value))
  end
end
