#!/bin/bash
# Cleanup script for orphaned test resources
# This script removes any resources created by integration tests that weren't properly cleaned up

set -e

# Regions the integration test, add more here if
# the test fixture starts targeting additional regions.
# To add a region later, REGIONS="us-west-2 us-west-1"
REGIONS="us-west-2"

echo "Cleaning up test resources..."
echo "Regions: $REGIONS"

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

# ── Regional resources ──────────────────────────────────────────────────────
for REGION in $REGIONS; do
  echo ""
  echo "==> Region: $REGION"

  # 1. Kinesis Analytics V2 (Managed Flink) applications.
  #    These hold open references to SQS, S3, log groups, and IAM roles, so delete
  #    them first. A RUNNING app refuses delete — force-stop it, then delete by
  #    create-timestamp.
  echo "  Deleting Flink applications..."
  aws kinesisanalyticsv2 list-applications --region "$REGION" \
    --query "ApplicationSummaries[?starts_with(ApplicationName, 'newrelic-fed-logs-') && contains(ApplicationName, 'inttest')].ApplicationName" \
    --output text 2>/dev/null | tr '\t' '\n' | \
  while read -r app; do
    if [ -n "$app" ]; then
      echo "    Stopping Flink application: $app"
      aws_cmd "stop Flink app $app" aws kinesisanalyticsv2 stop-application --region "$REGION" --application-name "$app" --force
      create_ts=$(aws kinesisanalyticsv2 describe-application --region "$REGION" --application-name "$app" \
        --query 'ApplicationDetail.CreateTimestamp' --output text 2>/dev/null || true)
      if [ -n "$create_ts" ] && [ "$create_ts" != "None" ]; then
        echo "    Deleting Flink application: $app"
        aws_cmd "delete Flink app $app" aws kinesisanalyticsv2 delete-application --region "$REGION" \
          --application-name "$app" --create-timestamp "$create_ts"
      fi
    fi
  done

  # 2. EventBridge rules. Targets must be removed before the rule can be deleted.
  echo "  Deleting EventBridge rules..."
  aws events list-rules --region "$REGION" \
    --query "Rules[?starts_with(Name, 'newrelic-fed-logs-') && contains(Name, 'inttest')].Name" \
    --output text 2>/dev/null | tr '\t' '\n' | \
  while read -r rule; do
    if [ -n "$rule" ]; then
      target_ids=$(aws events list-targets-by-rule --region "$REGION" --rule "$rule" \
        --query 'Targets[].Id' --output text 2>/dev/null | tr '\t' ' ')
      if [ -n "$target_ids" ]; then
        echo "    Removing targets for rule: $rule"
        aws_cmd "remove targets for rule $rule" aws events remove-targets --region "$REGION" --rule "$rule" --ids $target_ids
      fi
      echo "    Deleting EventBridge rule: $rule"
      aws_cmd "delete EventBridge rule $rule" aws events delete-rule --region "$REGION" --name "$rule"
    fi
  done

  # 3. CloudWatch metric alarms. One per partition table × 3 optimizer types.
  echo "  Deleting CloudWatch alarms..."
  alarm_names=$(aws cloudwatch describe-alarms --region "$REGION" \
    --query "MetricAlarms[?starts_with(AlarmName, 'newrelic_fed_logs_') && contains(AlarmName, 'inttest')].AlarmName" \
    --output text 2>/dev/null | tr '\t' ' ')
  if [ -n "$alarm_names" ]; then
    for a in $alarm_names; do
      echo "    Deleting alarm: $a"
    done
    aws_cmd "delete CloudWatch alarms" aws cloudwatch delete-alarms --region "$REGION" --alarm-names $alarm_names
  fi

  # 4. Glue triggers (data-retention scheduler). Trigger references the job, so
  #    delete the trigger first to allow the job to drop cleanly.
  echo "  Deleting Glue triggers..."
  aws glue list-triggers --region "$REGION" \
    --query "TriggerNames[?starts_with(@, 'newrelic_fed_logs_') && contains(@, 'inttest')]" \
    --output text 2>/dev/null | tr '\t' '\n' | \
  while read -r trig; do
    if [ -n "$trig" ]; then
      echo "    Deleting Glue trigger: $trig"
      aws_cmd "delete Glue trigger $trig" aws glue delete-trigger --region "$REGION" --name "$trig"
    fi
  done

  # 5. Glue jobs (data-retention Spark ETL).
  echo "  Deleting Glue jobs..."
  aws glue list-jobs --region "$REGION" \
    --query "JobNames[?starts_with(@, 'newrelic_fed_logs_') && contains(@, 'inttest')]" \
    --output text 2>/dev/null | tr '\t' '\n' | \
  while read -r job; do
    if [ -n "$job" ]; then
      echo "    Deleting Glue job: $job"
      aws_cmd "delete Glue job $job" aws glue delete-job --region "$REGION" --job-name "$job"
    fi
  done

  # 6. SQS queues.
  echo "  Deleting SQS queues..."
  aws sqs list-queues --region "$REGION" --queue-name-prefix "newrelic-fed-logs-" \
    --query 'QueueUrls[]' --output text 2>/dev/null | tr '\t' '\n' | \
  while read -r url; do
    if [ -n "$url" ]; then
      name=$(basename "$url")
      case "$name" in
        *inttest*)
          echo "    Deleting SQS queue: $name"
          aws_cmd "delete SQS queue $name" aws sqs delete-queue --region "$REGION" --queue-url "$url"
          ;;
      esac
    fi
  done

  # 7. CloudWatch log groups. Two known prefixes: Flink app + Glue retention job.
  echo "  Deleting CloudWatch log groups..."
  for lg_prefix in /aws/kinesis-analytics/newrelic-fed-logs- /aws-glue/jobs/newrelic_fed_logs_; do
    aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "$lg_prefix" \
      --query 'logGroups[].logGroupName' --output text 2>/dev/null | tr '\t' '\n' | \
    while read -r lg; do
      if [ -n "$lg" ]; then
        case "$lg" in
          *inttest*)
            echo "    Deleting log group: $lg"
            aws_cmd "delete log group $lg" aws logs delete-log-group --region "$REGION" --log-group-name "$lg"
            ;;
        esac
      fi
    done
  done

  # 8. Glue catalog databases.
  echo "  Deleting Glue databases..."
  aws glue get-databases --region "$REGION" \
    --query "DatabaseList[?starts_with(Name, 'newrelic_fed_logs_') && contains(Name, 'inttest')].Name" \
    --output text 2>/dev/null | tr '\t' '\n' | \
  while read -r db; do
    if [ -n "$db" ]; then
      echo "    Deleting Glue database: $db"
      aws glue get-tables --region "$REGION" --database-name "$db" \
        --query 'TableList[].Name' --output text 2>/dev/null | tr '\t' '\n' | \
      while read -r table; do
        if [ -n "$table" ]; then
          echo "      Deleting table: $table"
          aws_cmd "delete Glue table $db.$table" aws glue delete-table --region "$REGION" --database-name "$db" --name "$table"
        fi
      done
      aws_cmd "delete Glue database $db" aws glue delete-database --region "$REGION" --name "$db"
    fi
  done
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
aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, 'newrelic-fed-logs-') && contains(Name, 'inttest')].Name" \
  --output text 2>/dev/null | tr '\t' '\n' | \
while read -r bucket; do
  if [ -n "$bucket" ]; then
    echo "    Deleting bucket: $bucket"
    aws_cmd "remove S3 bucket $bucket" aws s3 rb "s3://$bucket" --force
  fi
done

# 10. IAM roles. Detach managed policies + delete inline policies before delete.
echo "  Deleting IAM roles..."
aws iam list-roles \
  --query "Roles[?starts_with(RoleName, 'newrelic-fed-logs-') && contains(RoleName, 'inttest')].RoleName" \
  --output text 2>/dev/null | tr '\t' '\n' | \
while read -r role; do
  if [ -n "$role" ]; then
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
done

# 11. IAM customer-managed policies.
echo "  Deleting IAM policies..."
aws iam list-policies --scope Local \
  --query "Policies[?starts_with(PolicyName, 'newrelic-fed-logs-') && contains(PolicyName, 'inttest')].Arn" \
  --output text 2>/dev/null | tr '\t' '\n' | \
while read -r policy_arn; do
  if [ -n "$policy_arn" ]; then
    echo "    Deleting IAM policy: $policy_arn"
    aws_cmd "delete IAM policy $policy_arn" aws iam delete-policy --policy-arn "$policy_arn"
  fi
done

echo ""
echo "Cleanup completed!"
