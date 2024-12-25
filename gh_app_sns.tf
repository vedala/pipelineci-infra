resource "aws_sns_topic" "pipelineci_sns_runner_topic" {
  name = "pipelineci-runner-topic"
}

resource "aws_sns_topic_subscription" "pipelineci_sns_runner_subscription" {
  topic_arn = aws_sns_topic.pipelineci_sns_runner_topic.arn
  protocol  = "https"
  endpoint  = "https://${var.RUNNER_SUBDOMAIN}.${var.DOMAIN_NAME}:${var.RUNNER_PORT}"
}
