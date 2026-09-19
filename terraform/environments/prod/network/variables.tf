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
    error_message = "terraform/environments/prod/network only accepts environment = \"prod\"."
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

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (ALB, NAT instance)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (EKS nodes, RDS)"
  type        = list(string)
}

variable "availability_zones" {
  description = "AZs for subnets"
  type        = list(string)
}
