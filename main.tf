data "archive_file" "dependency_layer" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/layer"
  output_path = "${path.module}/zips/lambda-layer.zip"
  depends_on  = [null_resource.dependency_layer_builder]
}

data "archive_file" "zip_the_js_code" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/dist"
  output_path = "${path.module}/zips/functions.zip"
  depends_on  = [null_resource.build_js_code]
}

resource "null_resource" "build_js_code" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/lambda"
    command     = "npm run build"
  }
}

resource "null_resource" "dependency_layer_builder" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    working_dir = "${path.module}/lambda"
    command     = <<EOT
npm install
rm -rf layer/nodejs
mkdir -p layer/nodejs
cp -r node_modules layer/nodejs
EOT
  }

}

resource "aws_iam_role" "lambda_role" {
  name = "Lambda_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "iam_lambda_policy" {
  name        = "IAM_Policy"
  description = "Logs policy for Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource : "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.iam_lambda_policy.arn
}

resource "aws_lambda_layer_version" "lambda_layer" {
  filename            = data.archive_file.dependency_layer.output_path
  layer_name          = "lambda-layer"
  source_code_hash    = data.archive_file.dependency_layer.output_base64sha256
  compatible_runtimes = ["nodejs20.x"]
}

resource "aws_lambda_function" "graphql_test_lambda_function" {
  function_name    = "graphql_test_lambda_function"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = data.archive_file.zip_the_js_code.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.zip_the_js_code.output_path
  layers           = [aws_lambda_layer_version.lambda_layer.arn]
  depends_on       = [aws_iam_role_policy_attachment.lambda_role_policy_attachment]
}

resource "aws_api_gateway_rest_api" "graphql_api" {
  name        = "graphql_api"
  description = "API Gateway for GraphQL"
}

resource "aws_api_gateway_resource" "graphql_resource" {
  rest_api_id = aws_api_gateway_rest_api.graphql_api.id
  parent_id   = aws_api_gateway_rest_api.graphql_api.root_resource_id
  path_part   = "graphql"
}

resource "aws_api_gateway_method" "graphql_method" {
  rest_api_id   = aws_api_gateway_rest_api.graphql_api.id
  resource_id   = aws_api_gateway_resource.graphql_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "graphql_integration" {
  rest_api_id             = aws_api_gateway_rest_api.graphql_api.id
  resource_id             = aws_api_gateway_resource.graphql_resource.id
  http_method             = aws_api_gateway_method.graphql_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.graphql_test_lambda_function.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.graphql_test_lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.graphql_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "graphql_deployment" {
  depends_on  = [aws_api_gateway_integration.graphql_integration]
  rest_api_id = aws_api_gateway_rest_api.graphql_api.id
  stage_name  = "test"
}