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

variable "my_ip" {
  description = "Laptop public IP as x.x.x.x/32 for the EKS API. Pass at plan/apply; never put in tfvars."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && endswith(var.my_ip, "/32")
    error_message = "my_ip must be a single host CIDR (x.x.x.x/32)."
  }
}

variable "enable_observability" {
  description = "Create the tainted t4g.large for Prometheus. Default false. Pass -var=enable_observability=true only for a short observability session; the next apply without it removes that node."
  type        = bool
  default     = false
}

variable "openai_api_key" {
  description = "OpenAI API key. Empty skips petclinic/dev/openai-api-key (ADR-0017). Pass via -var or TF_VAR_openai_api_key; never put in tfvars."
  type        = string
  default     = ""
  sensitive   = true
}
