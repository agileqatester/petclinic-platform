variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group (two AZs required even when single-AZ)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Existing VPC RDS security group ID (3306 from node SG). Do not create a second RDS SG."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "engine_version" {
  description = "MySQL engine version (major 8.4)"
  type        = string
  default     = "8.4"
}

variable "parameter_group_family" {
  description = "DB parameter group family"
  type        = string
  default     = "mysql8.4"
}

variable "db_name" {
  description = "Shared database name (ADR-0003)"
  type        = string
  default     = "petclinic"
}

variable "username" {
  description = "Master username"
  type        = string
  default     = "petclinic"
}

variable "allocated_storage" {
  description = "Initial storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Max storage in GB. Equal to allocated_storage disables autoscaling (sent to AWS as 0)."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention in days"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on delete"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Deletion protection"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
