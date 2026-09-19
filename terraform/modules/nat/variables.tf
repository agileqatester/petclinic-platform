variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR allowed to send traffic through the NAT instance"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs; NAT is placed in the first subnet (AZ-a)"
  type        = list(string)
}

variable "instance_type" {
  description = "NAT instance type. t4g.micro — t4g.nano often OOMs during cloud-init."
  type        = string
  default     = "t4g.micro"
}

variable "enable_ssm" {
  description = "Attach SSM instance profile (no SSH)"
  type        = bool
  default     = true
}

variable "ami_id" {
  description = "Optional AL2023 ARM AMI. Empty uses the latest AL2023 arm64 AMI."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
