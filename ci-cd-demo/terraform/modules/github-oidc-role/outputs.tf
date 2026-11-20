output "role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  value       = aws_iam_role.this.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider (created or looked up)."
  value       = local.oidc_provider_arn
}

output "oidc_subject" {
  description = "The exact `sub` claim the trust policy accepts."
  value       = local.oidc_subject
}
