data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

module "state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.18"

  bucket        = local.bucket_name
  force_destroy = false

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      bucket_key_enabled = true
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  lifecycle_rule = [
    {
      id      = "expire-noncurrent-state-versions"
      enabled = true
      filter  = {}

      abort_incomplete_multipart_upload_days = 7

      noncurrent_version_expiration = {
        noncurrent_days = var.noncurrent_version_retention_days
      }
    }
  ]
}
