variable "aws_region" {
  description = "AWS region for this environment"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (must be prod in this root module)"
  type        = string
  default     = "prod"

  validation {
    condition     = var.environment == "prod"
    error_message = "terraform/environments/prod/workload only accepts environment = \"prod\"."
  }
}

variable "project" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "petclinic"
}

variable "aws_account_id" {
  description = "AWS account this environment is allowed to target"
  type        = string
  default     = "833123247984"
}

variable "nat_instance_type" {
  description = "NAT instance type"
  type        = string
  default     = "t4g.micro"
}
