locals {
  name_prefix = "${var.project}-${var.environment}"
  identifier  = "${local.name_prefix}-mysql"
  # Spec table lists max_allocated_storage = allocated_storage (autoscaling off).
  # RDS requires max > allocated to enable autoscaling; 0 disables it.
  max_allocated_storage = var.max_allocated_storage > var.allocated_storage ? var.max_allocated_storage : 0
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-mysql"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-mysql-subnet-group"
  })
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${local.name_prefix}-mysql-"
  family      = var.parameter_group_family
  description = "utf8mb4 for ${local.identifier}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-mysql-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_password" "master" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds" {
  # checkov:skip=CKV_AWS_149:AWS-managed aws/secretsmanager key (ADR-0012)
  # checkov:skip=CKV2_AWS_57:Rotation is E-7; recovery_window 0 so destroy leaves no replica (ADR-0015)
  name                    = "${var.project}/${var.environment}/rds-credentials"
  description             = "RDS master credentials for ${local.identifier}"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.master.result
  })
}

resource "aws_db_instance" "this" {
  # checkov:skip=CKV_AWS_157:Single-AZ by design (ADR-0006)
  # checkov:skip=CKV_AWS_129:Enhanced monitoring extra CloudWatch cost; not in the $20 course cap
  # checkov:skip=CKV_AWS_118:IAM DB auth unused; app uses Secrets Manager password
  # checkov:skip=CKV_AWS_161:IAM DB auth unused; app uses Secrets Manager password
  # checkov:skip=CKV_AWS_293:Dev deletion_protection=false so workload destroy works (ADR-0015)
  # checkov:skip=CKV_AWS_353:Performance Insights extra cost; not in the $20 course cap
  # checkov:skip=CKV_AWS_354:Performance Insights KMS unused (PI disabled)
  identifier     = local.identifier
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = var.db_name
  port           = 3306

  username = var.username
  password = random_password.master.result

  allocated_storage          = var.allocated_storage
  max_allocated_storage      = local.max_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [var.security_group_id]
  parameter_group_name       = aws_db_parameter_group.this.name
  publicly_accessible        = false
  multi_az                   = var.multi_az
  backup_retention_period    = var.backup_retention_period
  skip_final_snapshot        = var.skip_final_snapshot
  deletion_protection        = var.deletion_protection
  copy_tags_to_snapshot      = true
  apply_immediately          = true
  auto_minor_version_upgrade = true
  delete_automated_backups   = true

  tags = merge(var.tags, {
    Name = local.identifier
  })
}
