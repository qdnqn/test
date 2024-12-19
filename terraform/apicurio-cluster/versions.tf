terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket = "$TERRAFORM_STATE_NAME"
    region = "eu-west-2"
    key    = "cluster-terraform.tfstate"
  }
}
