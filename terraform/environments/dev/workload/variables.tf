variable "aws_region" {
  description = "AWS region for this environment"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (must be dev in this root module)"
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "terraform/environments/dev/workload only accepts environment = \"dev\"."
  }
}

variable "project" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "petclinic"
}

variable "aws_account_id" {
  description = "AWS account this environment is allowed to target. Set in terraform.tfvars (never commit)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID in terraform.tfvars."
  }
}

variable "nat_instance_type" {
  description = "NAT instance type"
  type        = string
  default     = "t4g.micro"
}
