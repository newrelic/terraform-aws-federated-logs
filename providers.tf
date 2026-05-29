terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    newrelic = {
      source  = "newrelic/newrelic"
      version = ">= 3.62.0"
    }
  }
}

provider "newrelic" {
  region     = var.newrelic_region
  account_id = var.newrelic_account_id
}

