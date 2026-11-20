provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = local.name_prefix
      Task      = "3.49"
      ManagedBy = "terraform"
    }
  }
}
