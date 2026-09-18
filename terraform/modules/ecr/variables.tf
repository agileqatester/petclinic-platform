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
  description = "Service names for repos"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability (MUTABLE for dev, IMMUTABLE for prod)"
  type        = string
  default     = "MUTABLE"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
