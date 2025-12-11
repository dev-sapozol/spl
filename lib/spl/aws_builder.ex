defmodule Spl.AwsBuilder do
  require Logger

  def aws_account_id do
    Application.get_env(:spl, :aws)[:aws_account_id]
  end

  @region "us-east-1"

  defp env, do: System.get_env("ENV", "dev")

  def build_queue_arn_fifo(queue_name) do
    "arn:aws:sqs:#{@region}:#{aws_account_id()}:#{queue_name}-#{env()}.fifo"
  end

  def build_queue_https_fifo(queue_http) do
    "https://sqs.#{@region}.amazonaws.com/#{aws_account_id()}/#{queue_http}-#{env()}.fifo"
  end

  def build_ses_s3_queue do
    "https://sqs.#{@region}.amazonaws.com/#{aws_account_id()}/ses-receive-email"
  end
end
