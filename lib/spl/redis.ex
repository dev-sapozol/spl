defmodule Spl.Redis do
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start:
        {Redix, :start_link,
         [
           redis_url(),
           [
             name: __MODULE__,
             ssl: true,
             socket_opts: [
               {:verify, :verify_peer},
               {:server_name_indication, redis_host()},
               {:customize_hostname_check,
                [
                  match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
                ]}
             ]
           ]
         ]}
    }
  end

  defp redis_url do
    Application.fetch_env!(:spl, :redis)[:url]
  end

  defp redis_host do
    redis_url()
    |> URI.parse()
    |> Map.get(:host)
    |> to_charlist()
  end
end
