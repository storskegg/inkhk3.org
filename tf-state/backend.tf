terraform {
  backend "s3" {
    bucket       = "inkhk3-terraform-state-076479453187"
    key          = "tf-state/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
