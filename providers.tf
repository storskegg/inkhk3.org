terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  alias  = "acm"
  region = "us-east-2"
}

provider "aws" {
  region = "us-east-2"
}
