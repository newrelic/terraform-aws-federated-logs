# For any setup where data retention or snapshot tagging was already on, the
# code-artifacts bucket exists in state as aws_s3_bucket.retention_scripts[0].
# The bucket is now unconditional (no count), so its address is
# aws_s3_bucket.retention_scripts. This re-points existing state at the new
# address instead of destroying and recreating the bucket.
moved {
  from = aws_s3_bucket.retention_scripts[0]
  to   = aws_s3_bucket.retention_scripts
}
