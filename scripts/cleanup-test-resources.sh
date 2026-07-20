#!/bin/bash
# Cleanup script for orphaned test resources
# This script removes any resources created by integration tests that weren't properly cleaned up

set -e

# Regions the integration test, add more here if
# the test fixture starts targeting additional regions.
# To add a region later, REGIONS="us-west-2 us-west-1"
REGIONS="us-west-2"

NEWRELIC_FED_LOGS_NAME_PREFIX="newrelic-fed-logs-"
NEWRELIC_FED_LOGS_NAME_PREFIX_UNDERSCORE="newrelic_fed_logs_"
INTEGRATION_TEST_MARKER="inttest"

echo "Cleaning up test resources..."
echo "Regions: $REGIONS"
echo "Filter: names starting with '${NEWRELIC_FED_LOGS_NAME_PREFIX}' or '${NEWRELIC_FED_LOGS_NAME_PREFIX_UNDERSCORE}' AND containing '${INTEGRATION_TEST_MARKER}'"

# aws_cmd LABEL AWS_ARGS...
# Prints "WARN: <LABEL> failed: <stderr>" on any other failure so orphans don't stay invisible.
aws_cmd() {
  local label="$1"; shift
  local err rc=0
  err=$("$@" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$err" in
      *NotFoundException*|*ResourceNotFound*|*NoSuchEntity*|*NoSuchBucket*|*NonExistentQueue*|*EntityNotFoundException*)
        : # expected: resource already gone
        ;;
      *)
        echo "    WARN: $label failed: $err"
        ;;
    esac
  fi
  return 0
}

report_count() {
  local label="$1" count="$2"
  if [ "$count" -eq 0 ]; then
    echo "    No ${label} found"
  else
    echo "    Processed ${count} ${label}"
  fi
}

# purge_bucket_versions BUCKET
# `aws s3 rb --force` only deletes current object versions; noncurrent versions
# and delete markers survive, leaving versioned buckets stuck as BucketNotEmpty.
# We explicitly enumerate + batch-delete both before calling rb. Loops until the
# bucket is empty.
purge_bucket_versions() {
  local bucket="$1"
  local batch count
  for _ in $(seq 1 20); do
    batch=$(aws s3api list-object-versions --bucket "$bucket" --max-items 1000 \
      --output json 2>/dev/null | \
      jq -c '{Objects: ((.Versions // []) + (.DeleteMarkers // [])) | map({Key, VersionId})}' 2>/dev/null)
    count=$(echo "$batch" | jq '.Objects | length' 2>/dev/null)
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
      return 0
    fi
    aws_cmd "purge $count versions from $bucket" \
      aws s3api delete-objects --bucket "$bucket" --delete "$batch"
  done
  echo "    WARN: gave up purging $bucket after 20 iterations; s3 rb will likely fail"
}

# ── Regional resources ──────────────────────────────────────────────────────
for REGION in $REGIONS; do
  echo ""
  echo "==> Region: $REGION"

  # 1. Kinesis Analytics V2 (Managed Flink) applications.
  #    These hold open references to SQS, S3, log groups, and IAM roles, so delete
  #    them first. A RUNNING app refuses delete — force-stop it, then delete by
  #    create-timestamp.
  echo "  Deleting Flink applications..."
  count=0
  while read -r app; do
    if [ -n "$app" ]; then
      count=$((count + 1))
      echo "    Stopping Flink application: $app"
      aws_cmd "stop Flink app $app" aws kinesisanalyticsv2 stop-application --region "$REGION" --application-name "$app" --force
      # Poll until the app leaves STOPPING/FORCE_STOPPING.
      status=""; create_ts=""
      for _ in $(seq 1 12); do
        read -r status create_ts <<< "$(aws kinesisanalyticsv2 describe-application --region "$REGION" --application-name "$app" \
          --query '[ApplicationDetail.ApplicationStatus, ApplicationDetail.CreateTimestamp]' \
          --output text 2>/dev/null || echo "")"
        case "$status" in
          READY) break ;;
          "")    break ;;  # app not found — already gone
          *)     sleep 5 ;;
        esac
      done
      if [ "$status" = "READY" ] && [ -n "$create_ts" ] && [ "$create_ts" != "None" ]; then
        echo "    Deleting Flink application: $app"
        aws_cmd "delete Flink app $app" aws kinesisanalyticsv2 delete-application --region "$REGION" \
          --application-name "$app" --create-timestamp "$create_ts"
      elif [ -n "$status" ]; then
        echo "    Flink app $app still in '$status' after 60s; skipping delete (next sweep will retry)"
      fi
    fi
  done < <(aws kinesisanalyticsv2 list-applications --region "$REGION" \
    --query "ApplicationSummaries[?starts_with(ApplicationName, '${NEWRELIC_FED_LOGS_NAME_PREFIX}') && contains(ApplicationName, '${INTEGRATION_TEST_MARKER}')].ApplicationName" \
    --output text 2>/dev/null | tr '\t' '\n')
  report_count "Flink application(s)" "$count"

  # 2. EventBridge rules. Targets must be removed before the rule can be deleted.
  echo "  Deleting EventBridge rules..."
  count=0
  while read -r rule; do
    if [ -n "$rule" ]; then
      count=$((count + 1))
      target_ids=$(aws events list-targets-by-rule --region "$REGION" --rule "$rule" \
        --query 'Targets[].Id' --output text 2>/dev/null | tr '\t' ' ')
      if [ -n "$target_ids" ]; then
        echo "    Removing targets for rule: $rule"
        aws_cmd "remove targets for rule $rule" aws events remove-targets --region "$REGION" --rule "$rule" --ids $target_ids
      fi
      echo "    Deleting EventBridge rule: $rule"
      aws_cmd "delete EventBridge rule $rule" aws events delete-rule --region "$REGION" --name "$rule"
    fi
  done < <(aws events list-rules --region "$REGION" \
    --query "Rules[?starts_with(Name, '${NEWRELIC_FED_LOGS_NAME_PREFIX}') && contains(Name, '${INTEGRATION_TEST_MARKER}')].Name" \
    --output text 2>/dev/null | tr '\t' '\n')
  report_count "EventBridge rule(s)" "$count"

  # 3. CloudWatch metric alarms. One per partition table × 3 optimizer types.
  echo "  Deleting CloudWatch alarms..."
  alarm_names=$(aws cloudwatch describe-alarms --region "$REGION" \
    --query "MetricAlarms[?starts_with(AlarmName, '${NEWRELIC_FED_LOGS_NAME_PREFIX_UNDERSCORE}') && contains(AlarmName, '${INTEGRATION_TEST_MARKER}')].AlarmName" \
    --output text 2>/dev/null | tr '\t' ' ')
  count=0
  if [ -n "$alarm_names" ]; then
    for a in $alarm_names; do
      count=$((count + 1))
      echo "    Deleting alarm: $a"
    done
    aws_cmd "delete CloudWatch alarms" aws cloudwatch delete-alarms --region "$REGION" --alarm-names $alarm_names
  fi
  report_count "CloudWatch alarm(s)" "$count"

  # 4. Glue triggers (data-retention scheduler). Trigger references the job, so
  #    delete the trigger first to allow the job to drop cleanly.
  echo "  Deleting Glue triggers..."
  count=0
  while read -r trig; do
    if [ -n "$trig" ]; then
      count=$((count + 1))
      echo "    Deleting Glue trigger: $trig"
      aws_cmd "delete Glue trigger $trig" aws glue delete-trigger --region "$REGION" --name "$trig"
    fi
  done < <(aws glue list-triggers --region "$REGION" \
    --query "TriggerNames[?starts_with(@, '${NEWRELIC_FED_LOGS_NAME_PREFIX_UNDERSCORE}') && contains(@, '${INTEGRATION_TEST_MARKER}')]" \
    --output text 2>/dev/null | tr '\t' '\n')
  report_count "Glue trigger(s)" "$count"

  # 5. Glue jobs (data-retention Spark ETL).
  echo "  Deleting Glue jobs..."
  count=0
  while read -r job; do
    if [ -n "$job" ]; then
      count=$((count + 1))
      echo "    Deleting Glue job: $job"
      aws_cmd "delete Glue job $job" aws glue delete-job --region "$REGION" --job-name "$job"
    fi
  done < <(aws glue list-jobs --region "$REGION" \
    --query "JobNames[?starts_with(@, '${NEWRELIC_FED_LOGS_NAME_PREFIX_UNDERSCORE}') && contains(@, '${INTEGRATION_TEST_MARKER}')]" \
    --output text 2>/dev/null | tr '\t' '\n')
  report_count "Glue job(s)" "$count"

  # 6. SQS queues.
  echo "  Deleting SQS queues..."
  count=0
  while read -r url; do
    if [ -n "$url" ]; then
      name=$(basename "$url")
      case "$name" in
        *"$INTEGRATION_TEST_MARKER"*)
          count=$((count + 1))
          echo "    Deleting SQS queue: $name"
          aws_cmd "delete SQS queue $name" aws sqs delete-queue --region "$REGION" --queue-url "$url"
          ;;
      esac
    fi
  done < <(aws sqs list-queues --region "$REGION" --queue-name-prefix "$NEWRELIC_FED_LOGS_NAME_PREFIX" \
    --query 'QueueUrls[]' --output text 2>/dev/null | tr '\t' '\n')
  report_count "SQS queue(s)" "$count"

  # 7. CloudWatch log groups. Two known prefixes: Flink app + Glue retention job.
  echo "  Deleting CloudWatch log groups..."
  count=0
  for lg_prefix in "/aws/kinesis-analytics/${NEWRELIC_FED_LOGS_NAME_PREFIX}" "/aws-glue/jobs/${NEWRELIC_FED_LOGS_NAME_PREFIX_UNDERSCORE}"; do
    while read -r lg; do
      if [ -n "$lg" ]; then
        case "$lg" in
          *"$INTEGRATION_TEST_MARKER"*)
            count=$((count + 1))
            echo "    Deleting log group: $lg"
            aws_cmd "delete log group $lg" aws logs delete-log-group --region "$REGION" --log-group-name "$lg"
            ;;
        esac
      fi
    done < <(aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "$lg_prefix" \
      --query 'logGroups[].logGroupName' --output text 2>/dev/null | tr '\t' '\n')
  done
  report_count "CloudWatch log group(s)" "$count"

  # 8. Glue catalog databases.
  echo "  Deleting Glue databases..."
  count=0
  while read -r db; do
    if [ -n "$db" ]; then
      count=$((count + 1))
      echo "    Deleting Glue database: $db"
      table_count=0
      while read -r table; do
        if [ -n "$table" ]; then
          table_count=$((table_count + 1))
          echo "      Deleting table: $table"
          aws_cmd "delete Glue table $db.$table" aws glue delete-table --region "$REGION" --database-name "$db" --name "$table"
        fi
      done < <(aws glue get-tables --region "$REGION" --database-name "$db" \
        --query 'TableList[].Name' --output text 2>/dev/null | tr '\t' '\n')
      report_count "table(s) in $db" "$table_count"
      aws_cmd "delete Glue database $db" aws glue delete-database --region "$REGION" --name "$db"
    fi
  done < <(aws glue get-databases --region "$REGION" \
    --query "DatabaseList[?starts_with(Name, '${NEWRELIC_FED_LOGS_NAME_PREFIX_UNDERSCORE}') && contains(Name, '${INTEGRATION_TEST_MARKER}')].Name" \
    --output text 2>/dev/null | tr '\t' '\n')
  report_count "Glue database(s)" "$count"
done

# ── Global resources ────────────────────────────────────────────────────────
# S3 listing is global; `aws s3 rb` discovers each bucket's region itself.
# IAM is global.

echo ""
echo "==> Global resources"

# 9. S3 buckets. `s3 rb --force` empties versioned + unversioned objects then
#    drops the bucket; this also covers aws_s3_object children (Flink JAR,
#    partition folder markers, retention scripts).
echo "  Deleting S3 buckets..."
count=0
while read -r bucket; do
  if [ -n "$bucket" ]; then
    count=$((count + 1))
    echo "    Deleting bucket: $bucket"
    # Purge all versions + delete markers first — required for versioned buckets
    # (e.g. the flink-jar bucket). No-op for non-versioned buckets.
    purge_bucket_versions "$bucket"
    aws_cmd "remove S3 bucket $bucket" aws s3 rb "s3://$bucket" --force
  fi
done < <(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${NEWRELIC_FED_LOGS_NAME_PREFIX}') && contains(Name, '${INTEGRATION_TEST_MARKER}')].Name" \
  --output text 2>/dev/null | tr '\t' '\n')
report_count "S3 bucket(s)" "$count"

# 10. IAM roles. Detach managed policies + delete inline policies before delete.
echo "  Deleting IAM roles..."
count=0
while read -r role; do
  if [ -n "$role" ]; then
    count=$((count + 1))
    echo "    Deleting IAM role: $role"
    for policy in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
      echo "      Detaching policy: $policy"
      aws_cmd "detach policy $policy from role $role" aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
    done
    for policy in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null); do
      echo "      Deleting inline policy: $policy"
      aws_cmd "delete inline policy $policy on role $role" aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
    done
    aws_cmd "delete IAM role $role" aws iam delete-role --role-name "$role"
  fi
done < <(aws iam list-roles \
  --query "Roles[?starts_with(RoleName, '${NEWRELIC_FED_LOGS_NAME_PREFIX}') && contains(RoleName, '${INTEGRATION_TEST_MARKER}')].RoleName" \
  --output text 2>/dev/null | tr '\t' '\n')
report_count "IAM role(s)" "$count"

# 11. IAM customer-managed policies.
echo "  Deleting IAM policies..."
count=0
while read -r policy_arn; do
  if [ -n "$policy_arn" ]; then
    count=$((count + 1))
    echo "    Deleting IAM policy: $policy_arn"
    aws_cmd "delete IAM policy $policy_arn" aws iam delete-policy --policy-arn "$policy_arn"
  fi
done < <(aws iam list-policies --scope Local \
  --query "Policies[?starts_with(PolicyName, '${NEWRELIC_FED_LOGS_NAME_PREFIX}') && contains(PolicyName, '${INTEGRATION_TEST_MARKER}')].Arn" \
  --output text 2>/dev/null | tr '\t' '\n')
report_count "IAM policy(ies)" "$count"

echo ""
echo "Cleanup completed!"
