output "openai_secret_arn" {
  description = "Secrets Manager ARN for petclinic/{env}/openai-api-key. Empty when openai_api_key is unset."
  value       = local.create_openai_secret ? aws_secretsmanager_secret.openai[0].arn : ""
  sensitive   = true
}
