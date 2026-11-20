################################################################################
# ECS Cluster + Fargate Service
################################################################################

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.6"

  cluster_name = local.cluster_name

  cluster_setting = [
    {
      name  = "containerInsights"
      value = var.container_insights ? "enabled" : "disabled"
    }
  ]

  cloudwatch_log_group_retention_in_days = var.log_retention_days

  cluster_capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 100
      base   = 1
    }
  }

  services = {
    (local.service_name) = {
      cpu    = var.task_cpu
      memory = var.task_memory

      desired_count = var.desired_count

      runtime_platform = {
        cpu_architecture        = "X86_64"
        operating_system_family = "LINUX"
      }

      # Start the new task before stopping the old one; roll back if it never stabilises.
      deployment_minimum_healthy_percent = 100
      deployment_maximum_percent         = 200
      deployment_circuit_breaker = {
        enable   = true
        rollback = true
      }

      enable_autoscaling     = false
      enable_execute_command = false

      # No ALB: the task is reachable directly on its public IP.
      subnet_ids            = module.vpc.public_subnets
      assign_public_ip      = true
      create_security_group = false
      security_group_ids    = [module.app_sg.id]

      # The app makes no AWS API calls, so no task role is needed.
      create_tasks_iam_role = false

      container_definitions = {
        (local.container_name) = {
          image     = local.container_image
          essential = true

          portMappings = [
            {
              name          = "http"
              containerPort = var.container_port
              hostPort      = var.container_port
              protocol      = "tcp"
            }
          ]

          healthCheck = {
            command     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}/', timeout=3)"]
            interval    = 15
            timeout     = 5
            retries     = 3
            startPeriod = 15
          }

          # gunicorn needs a writable temp directory for worker heartbeats.
          readonlyRootFilesystem = false

          enable_cloudwatch_logging              = true
          create_cloudwatch_log_group            = true
          cloudwatch_log_group_retention_in_days = var.log_retention_days
        }
      }
    }
  }
}
