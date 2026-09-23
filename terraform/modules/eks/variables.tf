variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "subnet_ids" {
  description = "Private subnet IDs for the cluster and managed node group"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Additional cluster security group ID (from VPC module)"
  type        = string
}

variable "node_sg_id" {
  description = "Node security group ID (from VPC module)"
  type        = string
}

variable "node_instance_types" {
  description = "Instance types for nodes"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for nodes"
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  description = "Min node count"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Max node count"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired node count"
  type        = number
  default     = 2
}

variable "enable_observability" {
  description = "Create the tainted t4g.large observability node group. False skips it so a normal apply does not pay for that instance."
  type        = bool
  default     = false
}

variable "observability_node_instance_types" {
  description = "Instance types for the tainted observability node group (Prometheus, Grafana, Alertmanager). Used only when enable_observability is true."
  type        = list(string)
  default     = ["t4g.large"]
}

variable "node_disk_size" {
  description = "Root volume size in GB (gp3, encrypted)"
  type        = number
  default     = 20
}

variable "cluster_log_retention_days" {
  description = "CloudWatch retention for control-plane logs"
  type        = number
  default     = 7
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to call the public EKS API (operator /32). Never 0.0.0.0/0."
  type        = list(string)

  validation {
    condition = length(var.api_allowed_cidrs) > 0 && alltrue([
      for cidr in var.api_allowed_cidrs :
      can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"
    ])
    error_message = "api_allowed_cidrs must be a non-empty list of CIDRs and must not include 0.0.0.0/0."
  }
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
