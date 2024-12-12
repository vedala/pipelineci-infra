
#
# Lambda for status updater
#

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_execution_policy" {
  name       = "lambda_execution_policy_attachment"
  roles      = [aws_iam_role.lambda_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_s3_bucket" "status_updater_lambda_bucket" {
  bucket = "status-updater-lambda"
}

resource "aws_s3_object" "status_updater_lambda_code" {
  bucket = aws_s3_bucket.status_updater_lambda_bucket.id
  key    = "status_updater_lambda.zip"
  source = "../../pipelineci-status-updater/status_updater_lambda.zip"
  etag   = filemd5("../../pipelineci-status-updater/status_updater_lambda.zip")
}

resource "aws_lambda_function" "status_updater_lambda" {
  function_name = "status_updater_lambda"
  s3_bucket     = aws_s3_bucket.status_updater_lambda_bucket.id
  s3_key        = aws_s3_object.status_updater_lambda_code.key
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_execution_role.arn

  environment {
    variables = {
      ENV = "production"
    }
  }
}

#
# API Gateway
#
resource "aws_apigatewayv2_api" "status_updater_lambda_api" {
  name          = "status-updater-api"
  protocol_type = "HTTP"
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.status_updater_lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.status_updater_lambda_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                = aws_apigatewayv2_api.status_updater_lambda_api.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.status_updater_lambda.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.status_updater_lambda_api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.status_updater_lambda_api.id
  name        = "$default"
  auto_deploy = true
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.status_updater_lambda_api.api_endpoint
}
