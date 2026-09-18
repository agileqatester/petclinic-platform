variable "domain_name" {
  description = "Domain name for the hosted zone"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
