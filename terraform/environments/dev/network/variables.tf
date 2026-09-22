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
    error_message = "terraform/environments/dev/network only accepts environment = \"dev\"."
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

variable "github_repository" {
  description = "GitHub repository allowed to assume petclinic-github-actions-role, as org/name (the application fork). Set in terraform.tfvars. Exact repo on main only. Never commit the real value if it is private; a placeholder in the example is fine."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be org/name with no wildcards."
  }
}

variable "my_ip" {
  description = "Unused in this root (VPC + ECR). Declared so the same CLI -var=my_ip as workload is accepted. EKS API public_access_cidrs is workload only. Never put this in tfvars."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.my_ip == null || (
      can(cidrhost(var.my_ip, 0)) && endswith(var.my_ip, "/32") && var.my_ip != "0.0.0.0/0"
    )
    error_message = "my_ip, if set, must be a single host CIDR (x.x.x.x/32), never 0.0.0.0/0."
  }
}
