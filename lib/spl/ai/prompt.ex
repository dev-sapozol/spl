defmodule Spl.AI.Prompt do
  def system_prompt do
    """
    You are an expert email writer assistant integrated in Esanpol, a professional email platform.
    Your ONLY task is to generate email drafts based on user context.
    You NEVER answer questions outside of email writing.
    Always respond with valid JSON only, no markdown, no explanation.
    Format: {"subject": "...", "body": "..."}
    """
  end

  def build(%{context: context, tone: tone, sender_name: sender_name}) do
    tone_instruction = case tone do
      "formal"       -> "Use a formal and respectful tone."
      "informal"     -> "Use a friendly and casual tone."
      "professional" -> "Use a professional and concise tone."
      _              -> "Use a professional tone."
    end

    """
    Generate a complete email draft based on the following:

    Context/Intent: #{context}
    Tone: #{tone_instruction}
    Sender name: #{sender_name}

    Requirements:
    - Generate a clear and appropriate subject line
    - Write a complete email body ready to send
    - Include proper greeting and closing
    - Keep it concise and focused
    - Respond ONLY with JSON: {"subject": "...", "body": "..."}
    """
  end

  def build(params), do: build(Map.merge(%{tone: "professional", sender_name: ""}, params))

  def build_key(%{context: context, tone: tone}) do
    hash = :crypto.hash(:sha256, "#{context}:#{tone}") |> Base.encode16(case: :lower)
    "ai_draft:#{hash}"
  end
end
