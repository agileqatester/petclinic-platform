locals {
  # count cannot take a sensitive value; only the empty-check is unwrapped.
  create_openai_secret = nonsensitive(var.openai_api_key) != ""
}

resource "aws_secretsmanager_secret" "openai" {
  # checkov:skip=CKV_AWS_149:AWS-managed aws/secretsmanager key (ADR-0012)
  # checkov:skip=CKV2_AWS_57:No rotation this epic; recovery_window 0 so destroy leaves no replica (ADR-0017)
  count = local.create_openai_secret ? 1 : 0

  name                    = "${var.project}/${var.environment}/openai-api-key"
  description             = "OpenAI API key for genai-service"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-openai-api-key"
  })
}

resource "aws_secretsmanager_secret_version" "openai" {
  count = local.create_openai_secret ? 1 : 0

  secret_id     = aws_secretsmanager_secret.openai[0].id
  secret_string = var.openai_api_key
}
