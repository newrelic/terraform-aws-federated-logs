terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.36.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    newrelic = {
      source  = "newrelic/newrelic"
      version = ">= 3.91.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

provider "newrelic" {
  account_id = 0 # Replace with your NR account ID.
  region     = "US"
  api_key    = var.newrelic_api_key
}
