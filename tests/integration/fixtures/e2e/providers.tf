terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.36.0"
    }
    newrelic = {
      source  = "newrelic/newrelic"
      version = ">= 3.91.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "newrelic" {
  region     = var.newrelic_region
  account_id = var.newrelic_account_id
}
