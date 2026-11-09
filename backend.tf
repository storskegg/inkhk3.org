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
