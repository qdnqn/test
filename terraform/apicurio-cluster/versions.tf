terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket = "ecs-api-curio-testing"
    region = "eu-west-2"
    key    = "cluster-terraform.tfstate"
  }
}
