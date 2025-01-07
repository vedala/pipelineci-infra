resource "aws_sns_topic" "pipelineci_sns_runner_topic" {
  name = "pipelineci-runner-topic"
}

resource "aws_sns_topic_subscription" "pipelineci_sns_runner_subscription" {
  topic_arn = aws_sns_topic.pipelineci_sns_runner_topic.arn
  protocol  = "https"
  endpoint  = "https://${var.RUNNER_SUBDOMAIN}.${var.DOMAIN_NAME}/run_ci"
}

resource "aws_iam_policy" "pipelineci_sns_policy" {
  name = "pipelineci_sns_policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sns:*",
        Resource: "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sns_role_attachment" {
  policy_arn  = aws_iam_policy.pipelineci_sns_policy.arn
  role        = aws_iam_role.ecs_execution_role.name
}
