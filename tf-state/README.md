# tf-state

A small standalone Terraform stack that holds the private S3 bucket for this repo's Terraform state
(`inkhk3-terraform-state-076479453187`, us-east-2). The root stack does not load this directory.

Both stacks keep their state in that bucket, under different keys: see `backend.tf` here and at the repo root.
Infrastructure changes are the user's.
