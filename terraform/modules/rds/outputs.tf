output "endpoint" {
  description = "RDS endpoint hostname"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}

output "secret_arn" {
  description = "Secrets Manager ARN for petclinic/{env}/rds-credentials"
  value       = aws_secretsmanager_secret.rds.arn
  sensitive   = true
}
