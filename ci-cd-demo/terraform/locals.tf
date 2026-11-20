data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name_prefix = "task-3-49"

  vpc_name           = "${local.name_prefix}-vpc"
  public_subnet_name = "${local.name_prefix}-public-subnet"
  security_group     = "${local.name_prefix}-sg"
  cluster_name       = "${local.name_prefix}-cluster"
  service_name       = "${local.name_prefix}-service"
  container_name     = "${local.name_prefix}-app"
  github_role_name   = "${local.name_prefix}-github-actions-role"
  deploy_policy_name = "${local.name_prefix}-deploy-policy"

  azs = slice(data.aws_availability_zones.available.names, 0, 1)

  container_image = "docker.io/${var.dockerhub_image}:latest"

  # Built from known names so IAM does not depend on the ECS module.
  ecs_service_arn = "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${local.cluster_name}/${local.service_name}"
}
