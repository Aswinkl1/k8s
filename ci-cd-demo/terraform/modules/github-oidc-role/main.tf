locals {
  oidc_host     = "token.actions.githubusercontent.com"
  oidc_url      = "https://${local.oidc_host}"
  oidc_audience = "sts.amazonaws.com"
  oidc_subject  = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

################################################################################
# OIDC Identity Provider
################################################################################

data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url = "${local.oidc_url}/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = local.oidc_url
  client_id_list  = [local.oidc_audience]
  thumbprint_list = distinct([for cert in data.tls_certificate.github[0].certificates : cert.sha1_fingerprint if cert.is_ca])

  tags = merge(var.tags, { Name = local.oidc_host })
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = local.oidc_url
}

################################################################################
# IAM Role
################################################################################

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.oidc_subject]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = var.role_description
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration

  tags = merge(var.tags, { Name = var.role_name })
}

################################################################################
# Permissions
################################################################################

data "aws_iam_policy_document" "permissions" {
  dynamic "statement" {
    for_each = var.policy_statements

    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = var.policy_name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}
