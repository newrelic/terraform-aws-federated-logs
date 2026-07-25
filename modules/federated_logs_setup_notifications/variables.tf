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
  description = "ARN of the SQS queue to send EventBridge events to. Fetched from the role module via NGEP. The account portion of this ARN is also what the module uses to detect cross-account delivery — when it differs from the current AWS account, an IAM role is created for EventBridge to assume so it can deliver to the cross-account queue."
  type        = string
}
