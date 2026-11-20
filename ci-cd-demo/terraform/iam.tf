################################################################################
# GitHub Actions OIDC deploy role
################################################################################

module "github_actions_role" {
  source = "./modules/github-oidc-role"

  create_oidc_provider = var.create_oidc_provider

  role_name        = local.github_role_name
  role_description = "Assumed by GitHub Actions (${var.github_owner}/${var.github_repo}@${var.github_branch}) to redeploy ${local.service_name}"

  github_owner  = var.github_owner
  github_repo   = var.github_repo
  github_branch = var.github_branch

  policy_name = local.deploy_policy_name
  policy_statements = [
    {
      sid       = "RedeployEcsService"
      actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
      resources = [local.ecs_service_arn]
    }
  ]
}
