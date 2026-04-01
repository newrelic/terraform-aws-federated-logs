# Variable values for this configuration

# AWS Configuration
aws_region     = "us-west-2"
aws_account_id = "864899866645" # Replace with your AWS account ID

# Naming prefix for S3 bucket and Glue catalog database
resource_naming_prefix = "rbandlamudifedlogsparamstest" # Must be lowercase alphanumeric, 3-40 characters, starting with a letter

clusters = {
  "cluster-1" = {
    k8s_namespace            = "federated-logs"
    k8s_service_account_name = "pcg-writer-sa"
    oidc_provider_arn        = "arn:aws:iam::864899866645:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/21565E3BA44FFF327119E343234BE2ED"
  }
}

partition_tables = {
  "Log_federated_application_log" = {
    # Orphan File Deletion params OPTIONAL
    orphan_file_deletion = {
      delete_after_days = 3
    }
    # Snapshot Retention params OPTIONAL
    snapshot_retention = {
      snapshot_retention_period_in_days = 5
      number_of_snapshots_to_retain     = 2
      clean_expired_files               = true
    }
    # Compaction related params OPTIONAL
    compaction_config = {
      min_input_files       = 50
      delete_file_threshold = 5
    }
  },
  "Log_federated_security_log" = {
    # Orphan File Deletion params OPTIONAL
    orphan_file_deletion = {
      delete_after_days = 3
    }
    # Snapshot Retention params OPTIONAL
    snapshot_retention = {
      snapshot_retention_period_in_days = 5
      number_of_snapshots_to_retain     = 2
      clean_expired_files               = true
    }
    # Compaction related params OPTIONAL
    compaction_config = {
      min_input_files       = 50
      delete_file_threshold = 5
    }
  }
}
