variable "setup_name" {
  description = "Name of the federated logs setup, used in resource naming."
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
  description = "ARN of the SQS queue to send EventBridge events to. Fetched from the role module via NGEP."
  type        = string
}

variable "target_account_id" {
  description = "AWS account ID hosting the SQS queue. When set and different from this account, the module creates an IAM role for EventBridge to assume so it can deliver to the cross-account queue, and wires that role onto the target via role_arn. Leave null for same-account deployments — EventBridge then invokes SQS directly using the queue's resource policy."
  type        = string
  default     = null
}
