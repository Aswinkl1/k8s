variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false if the AWS account already has one (only one per URL is allowed per account)."
  type        = bool
  default     = true
}

variable "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  type        = string
}

variable "role_description" {
  description = "Description of the IAM role."
  type        = string
  default     = "Assumed by GitHub Actions via OIDC"
}

variable "max_session_duration" {
  description = "Maximum session duration (seconds) for the role."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.github_owner))
    error_message = "github_owner must be a literal GitHub owner name (no wildcards)."
  }
}

variable "github_repo" {
  description = "GitHub repository name (without the owner)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must be a literal repository name (no wildcards)."
  }
}

variable "github_branch" {
  description = "Branch allowed to assume the role."
  type        = string
  default     = "main"

  validation {
    condition     = !strcontains(var.github_branch, "*")
    error_message = "github_branch must not contain wildcards."
  }
}

variable "policy_name" {
  description = "Name of the inline permissions policy attached to the role."
  type        = string
}

variable "policy_statements" {
  description = "IAM policy statements granted to the role. Keep these least-privilege and scoped to specific resource ARNs."
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
  }))

  validation {
    condition     = alltrue([for s in var.policy_statements : !contains(s.resources, "*")])
    error_message = "policy_statements must not use \"*\" as a resource; scope to specific ARNs."
  }
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
