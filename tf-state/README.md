# tf-state

A small standalone Terraform stack that creates the private S3 bucket holding the
Terraform state for inkhk3.org (us-east-2). The root stack does not load this
directory. The user applies it; this is a draft. The runbook is kept by WEB.

The two backend blocks below are text only. They must not become live `.tf`
files until the state is migrated.

## Root stack, `backend.tf` (add at the root only on migration)

```hcl
terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "inkhk3-terraform-state-076479453187"
    key          = "inkhk3.org/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

## This stack (`tf-state/`), added after the bucket exists

```hcl
terraform {
  backend "s3" {
    bucket       = "inkhk3-terraform-state-076479453187"
    key          = "tf-state/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
```
