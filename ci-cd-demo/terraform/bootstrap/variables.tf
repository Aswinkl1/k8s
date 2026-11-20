variable "aws_region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix used for resource naming."
  type        = string
  default     = "task-3-49"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "project must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep non-current versions of state files before expiring them."
  type        = number
  default     = 90
}
