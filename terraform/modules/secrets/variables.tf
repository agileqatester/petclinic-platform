variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "openai_api_key" {
  description = "OpenAI API key. Empty skips the secret (ADR-0017). Pass via -var or TF_VAR_openai_api_key; never commit."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
