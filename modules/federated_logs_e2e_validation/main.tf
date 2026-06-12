data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Max 12 chars so total resource names stay within AWS limits
  # (IAM role name_prefix has a 38-char ceiling).
  setup_id_short = var.setup_id == "" ? "default" : substr(
    replace(var.setup_id, "/[^a-zA-Z0-9]/", ""),
    0,
    12,
  )

  function_name = "nr-fed-logs-e2e-${local.setup_id_short}"
}

data "external" "nr_credentials" {
  program = ["python3", "${path.module}/scripts/read_credentials.py"]
}

resource "aws_secretsmanager_secret" "license_key" {
  name                    = "${local.function_name}-license-key"
  description             = "New Relic license key consumed by the federated-logs E2E validation Lambda."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "license_key" {
  secret_id     = aws_secretsmanager_secret.license_key.id
  secret_string = sensitive(data.external.nr_credentials.result.license_key)

  lifecycle {
    # Only the first apply writes the value. Subsequent applies don't
    # re-read state to drift-check, so the secret_string stays in state
    # but isn't repeatedly compared against fresh runner-env reads.
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "api_key" {
  name                    = "${local.function_name}-api-key"
  description             = "New Relic User API key consumed by the federated-logs E2E validation Lambda."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "api_key" {
  secret_id     = aws_secretsmanager_secret.api_key.id
  secret_string = sensitive(data.external.nr_credentials.result.api_key)

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# =============================================================================
# Lambda deployment package
#
# Zips scripts/ at apply time. source_code_hash drives function updates when
# the script changes — and feeds the invocation trigger so re-validation
# runs only when something changed (not on every apply).
# =============================================================================

data "archive_file" "e2e_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/scripts"
  output_path = "${path.module}/.terraform/e2e_lambda.zip"
  excludes    = ["__pycache__"]
}

# =============================================================================
# IAM — Lambda execution role
# =============================================================================

resource "aws_iam_role" "e2e_lambda" {
  name_prefix = "${local.function_name}-"
  description = "Execution role for the federated-logs E2E validation Lambda."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "e2e_lambda_basic" {
  role       = aws_iam_role.e2e_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "e2e_lambda_vpc" {
  role       = aws_iam_role.e2e_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "e2e_lambda_secrets" {
  name = "secrets-read"
  role = aws_iam_role.e2e_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.license_key.arn,
        aws_secretsmanager_secret.api_key.arn,
      ]
    }]
  })
}

# =============================================================================
# Lambda function
# =============================================================================

resource "aws_lambda_function" "e2e_validation" {
  function_name    = local.function_name
  description      = "Federated logs E2E validation: posts a synthetic log to PCG, polls NRDB, reports HEALTHY/UNHEALTHY."
  role             = aws_iam_role.e2e_lambda.arn
  filename         = data.archive_file.e2e_lambda.output_path
  source_code_hash = data.archive_file.e2e_lambda.output_base64sha256
  handler          = "lambda_handler.handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.vpc_config.subnet_ids
    security_group_ids = var.vpc_config.security_group_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.e2e_lambda_basic,
    aws_iam_role_policy_attachment.e2e_lambda_vpc,
    aws_iam_role_policy.e2e_lambda_secrets,
  ]
}

# =============================================================================
# Invocation
# =============================================================================

resource "aws_lambda_invocation" "e2e_validation" {
  function_name = aws_lambda_function.e2e_validation.function_name

  # The secret values must be in place before the Lambda runs (otherwise it
  # fetches an empty/missing version). depends_on ensures the secret_version
  # writes complete before the invocation fires.
  depends_on = [
    aws_secretsmanager_secret_version.license_key,
    aws_secretsmanager_secret_version.api_key,
  ]

  triggers = {
    always_run = timestamp()
  }

  input = jsonencode({
    pcg_endpoint           = var.pcg_endpoint
    nr_account_id          = var.nr_account_id
    nr_region              = var.nr_region
    setup_id               = var.setup_id
    test_payload           = var.test_payload
    license_key_secret_arn = aws_secretsmanager_secret.license_key.arn
    api_key_secret_arn     = aws_secretsmanager_secret.api_key.arn
    max_retries            = var.max_retries
    retry_delay            = var.retry_delay
    initial_read_wait      = var.initial_read_wait
    read_max_retries       = var.read_max_retries
    read_retry_delay       = var.read_retry_delay
  })
}
