terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.58.0" # compaction_configuration on aws_glue_catalog_table_optimizer
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    newrelic = {
      source  = "newrelic/newrelic"
      version = ">= 3.91.0"
    }
  }
}

