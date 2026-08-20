variable "setup_name" {
  description = "Name of the federated logs setup, used in resource naming."
  type        = string
}

variable "setup_id" {
  description = "Entity GUID of the parent newrelic_federated_logs_setup. Injected into the EventBridge message for the Flink commit worker to stamp onto commit metrics — distinct from setup_name, which is a human-readable name and not guaranteed unique."
  type        = string
}

variable "s3_bucket_id" {
  description = "ID of the S3 bucket to enable EventBridge notifications on."
  type        = string
}

variable "pcg_writer_role_arn" {
  description = "ARN of the PCG writer IAM role. Injected into EventBridge message for Flink commit worker to AssumeRole."
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue to send EventBridge events to. Fetched from the role module via NGEP. The account portion of this ARN is also what the module uses to detect cross-account delivery — when it differs from the current AWS account, an IAM role is created for EventBridge to assume so it can deliver to the cross-account queue."
  type        = string
}
