defmodule SplWeb.AIDraftController do
  use SplWeb, :controller
  require Logger
  alias Spl.AI.EmailDraftRouter
  alias Spl.Account.User
  alias Spl.Repo
  import Ecto.Query

  @max_messages 8

  def generate(conn, %{"context" => context} = params) do
    user = conn.assigns[:current_user]

    if user.ai_messages_used >= @max_messages do
      conn
      |> put_status(403)
      |> json(%{
        error: :limit_reached
      })
    else
      draft_params = %{
        context: context,
        tone: Map.get(params, "tone", "professional"),
        sender_name: user.name
      }

      case EmailDraftRouter.generate_draft(draft_params) do
        {:ok, draft} ->
          used =
            if Map.get(draft, :from_cache, false) do
              user.ai_messages_used
            else
              increment_ai_usage(user.id)
              user.ai_messages_used + 1
            end

          remaining = @max_messages - used

          json(conn, %{
            success: true,
            subject: draft.subject,
            body: draft.body,
            from_cache: Map.get(draft, :from_cache, false),
            ai_messages_remaining: remaining
          })

        {:error, :out_of_scope} ->
          conn
          |> put_status(422)
          |> json(%{error: "This request is outside the email assistant scope."})

        {:error, :all_providers_failed} ->
          conn
          |> put_status(503)
          |> json(%{error: "AI service temporarily unavailable. Please try again later."})

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: inspect(reason)})
      end
    end
  end

  def generate(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing required field: context"})
  end

  defp increment_ai_usage(user_id) do
    {_, _} =
      from(u in User, where: u.id == ^user_id)
      |> Repo.update_all(inc: [ai_messages_used: 1])
  end
end
