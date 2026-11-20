terraform {
  # Partial configuration: bucket, key and region come from backend.hcl
  # (terraform init -backend-config=backend.hcl).
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
