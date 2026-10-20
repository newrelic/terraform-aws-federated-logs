# The code-artifacts bucket was first added as
# aws_s3_bucket.retention_scripts[0] (count-gated on data retention, later
# also snapshot tagging). It is now unconditional and renamed to
# aws_s3_bucket.code_artifacts, since it holds more than the retention
# script. These blocks re-point existing state at the new addresses instead
# of destroying and recreating the bucket and its policy.
moved {
  from = aws_s3_bucket.retention_scripts[0]
  to   = aws_s3_bucket.code_artifacts
}

moved {
  from = aws_s3_bucket_policy.retention_scripts
  to   = aws_s3_bucket_policy.code_artifacts
}
