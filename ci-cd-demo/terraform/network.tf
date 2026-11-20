################################################################################
# VPC - single AZ, single public subnet, IGW, no NAT
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.8"

  name = local.vpc_name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets      = [var.public_subnet_cidr]
  public_subnet_names = [local.public_subnet_name]

  create_igw         = true
  enable_nat_gateway = false

  enable_dns_support   = true
  enable_dns_hostnames = true

  # Fargate tasks get a public IP from the service network configuration.
  map_public_ip_on_launch = false

  # Adopt the default SG and strip all rules so nothing uses it by accident.
  manage_default_security_group = true
  default_security_group_name   = "${local.name_prefix}-default-sg"

  igw_tags                = { Name = "${local.name_prefix}-igw" }
  public_route_table_tags = { Name = "${local.name_prefix}-public-rt" }
}

################################################################################
# Security Group for the Fargate task
################################################################################

module "app_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name            = local.security_group
  use_name_prefix = false
  description     = "Allow inbound to the Flask app and all outbound (Docker Hub pulls)"
  vpc_id          = module.vpc.vpc_id

  ingress_rules = {
    app = {
      description = "Flask app"
      ip_protocol = "tcp"
      from_port   = var.container_port
      to_port     = var.container_port
      cidr_ipv4   = var.app_ingress_cidr
    }
  }

  egress_rules = {
    all = {
      description = "All outbound (image pulls, CloudWatch Logs)"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = { Name = local.security_group }
}
