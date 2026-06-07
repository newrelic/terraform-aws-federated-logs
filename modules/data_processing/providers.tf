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
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}
