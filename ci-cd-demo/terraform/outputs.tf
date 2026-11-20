################################################################################
# GitHub Actions
################################################################################

output "github_actions_role_arn" {
  description = "Set this as the GitHub repository variable AWS_ROLE_ARN."
  value       = module.github_actions_role.role_arn
}

output "github_oidc_subject" {
  description = "The only OIDC `sub` claim allowed to assume the deploy role."
  value       = module.github_actions_role.oidc_subject
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider."
  value       = module.github_actions_role.oidc_provider_arn
}

################################################################################
# ECS
################################################################################

output "ecs_cluster_name" {
  description = "ECS cluster name (ECS_CLUSTER in the workflow)."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name (ECS_SERVICE in the workflow)."
  value       = module.ecs.services[local.service_name].name
}

output "ecs_service_arn" {
  description = "ARN of the ECS service; the deploy policy is scoped to this."
  value       = module.ecs.services[local.service_name].id
}

output "container_image" {
  description = "Image the task definition pulls."
  value       = local.container_image
}

################################################################################
# Networking
################################################################################

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "Public subnet ID the Fargate task runs in."
  value       = module.vpc.public_subnets[0]
}

output "security_group_id" {
  description = "Security group attached to the Fargate task."
  value       = module.app_sg.id
}

################################################################################
# Helpers
################################################################################

output "get_task_public_ip_command" {
  description = "Prints the public IP of the running task. The IP changes on every deployment, so Terraform cannot output it directly."
  value       = <<-EOT
    TASK_ARN=$(aws ecs list-tasks --region ${var.aws_region} --cluster ${local.cluster_name} --service-name ${local.service_name} --desired-status RUNNING --query 'taskArns[0]' --output text) && \
    ENI_ID=$(aws ecs describe-tasks --region ${var.aws_region} --cluster ${local.cluster_name} --tasks "$TASK_ARN" --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text) && \
    aws ec2 describe-network-interfaces --region ${var.aws_region} --network-interface-ids "$ENI_ID" --query 'NetworkInterfaces[0].Association.PublicIp' --output text
  EOT
}
