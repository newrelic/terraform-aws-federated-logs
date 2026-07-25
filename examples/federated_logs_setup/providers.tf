terraform {
  required_version = ">= 1.6.0"
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
  region = "us-east-2"
}

# The federated-logs module no longer configures the `newrelic` provider
# itself — root configurations must declare it. `account_id` and `region`
# here must match the values passed to the module.
provider "newrelic" {
  account_id = 0    # Replace with your NR account ID.
  region     = "US" # "US" (default), "EU", or "STAGING"
}
