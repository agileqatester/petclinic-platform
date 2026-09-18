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
    error_message = "terraform/environments/dev only accepts environment = \"dev\"."
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
