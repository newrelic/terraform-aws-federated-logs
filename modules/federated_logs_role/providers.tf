terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
    newrelic = {
      source  = "newrelic/newrelic"
      version = ">= 3.62.0"
    }
  }
}

