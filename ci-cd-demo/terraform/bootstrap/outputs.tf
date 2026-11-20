output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Use it as `bucket` in ../backend.hcl."
  value       = module.state_bucket.s3_bucket_id
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket."
  value       = module.state_bucket.s3_bucket_arn
}

output "aws_region" {
  description = "Region of the Terraform state bucket. Use it as `region` in ../backend.hcl."
  value       = var.aws_region
}
