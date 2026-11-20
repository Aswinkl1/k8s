################################################################################
# General
################################################################################

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

################################################################################
# Networking
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet. Must be inside vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "app_ingress_cidr" {
  description = "CIDR allowed to reach the app port. The task requires 0.0.0.0/0; narrow this to your IP outside of the demo."
  type        = string
  default     = "0.0.0.0/0"
}

################################################################################
# Application / ECS
################################################################################

variable "dockerhub_image" {
  description = "Docker Hub repository in the form <username>/<image> (without tag). The :latest tag is always used."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*/[a-z0-9]+(?:[._-][a-z0-9]+)*$", var.dockerhub_image))
    error_message = "dockerhub_image must look like <username>/<image> with no tag."
  }
}

variable "container_port" {
  description = "Port the Flask/gunicorn container listens on."
  type        = number
  default     = 5000
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "CloudWatch log retention for container logs."
  type        = number
  default     = 7
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster (extra cost)."
  type        = bool
  default     = false
}

################################################################################
# GitHub OIDC
################################################################################

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false if one already exists in the account."
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without owner)."
  type        = string
}

variable "github_branch" {
  description = "Only workflows running on this branch can assume the deploy role."
  type        = string
  default     = "main"
}
