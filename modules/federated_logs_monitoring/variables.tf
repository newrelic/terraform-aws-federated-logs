variable "newrelic_account_id" {
  description = "New Relic account ID where the dashboard will be created."
  type        = number
}

variable "setup_name" {
  description = "Federated logs setup name."
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket used for federated logs data."
  type        = string
}

variable "glue_catalog_db_name" {
  description = "Name of the Glue catalog database."
  type        = string
}

variable "sqs_queue_arn" {
  description = "SQS queue ARN from the fleet entity."
  type        = string
}

variable "dashboard_name" {
  description = "Name of the dashboard. Defaults to 'Federated Logs - <setup_name>'."
  type        = string
  default     = null
}

variable "partition_table_ids" {
  description = "Map of tableId (database.table) to partition display name (e.g. Log_Federated). Sourced from the partition module's all_table_ids output. Used to seed the dashboard partition dropdown so it is always populated regardless of metric history."
  type        = map(string)
  default     = {}
}

variable "pcg_cluster_name" {
  description = "EKS cluster name where PCG is running. Used to filter PCG metrics in the dashboard. If not provided, the PCG Metrics page will appear but show no data."
  type        = string
  default     = ""
}
