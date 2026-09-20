variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "service_names" {
  description = "Service names for repos (one repository each under petclinic-{env}/)"
  type        = list(string)

  validation {
    condition     = length(var.service_names) > 0
    error_message = "service_names must include at least one service."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability (MUTABLE for dev, IMMUTABLE for prod)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
