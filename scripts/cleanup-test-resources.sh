#!/bin/bash
# Cleanup script for orphaned test resources
# This script removes any resources created by integration tests that weren't properly cleaned up

set -e

# Regions to sweep. Defaults to AWS_REGION + us-west-2 (the region the Go integration test pins,
# regardless of the workflow's AWS_REGION env). Override with TEST_REGIONS="r1,r2,...".
DEFAULT_REGIONS="${AWS_REGION:-us-east-1} us-west-2"
TEST_REGIONS_INPUT="${TEST_REGIONS:-$DEFAULT_REGIONS}"
REGIONS=$(echo "$TEST_REGIONS_INPUT" | tr ',' ' ' | tr -s ' ' '\n' | awk 'NF && !seen[$0]++' | xargs)

echo "Cleaning up test resources..."
echo "Sweeping regions: $REGIONS"

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
      aws kinesisanalyticsv2 stop-application --region "$REGION" --application-name "$app" --force 2>/dev/null || true
      create_ts=$(aws kinesisanalyticsv2 describe-application --region "$REGION" --application-name "$app" \
        --query 'ApplicationDetail.CreateTimestamp' --output text 2>/dev/null || true)
      if [ -n "$create_ts" ] && [ "$create_ts" != "None" ]; then
        echo "    Deleting Flink application: $app"
        aws kinesisanalyticsv2 delete-application --region "$REGION" \
          --application-name "$app" --create-timestamp "$create_ts" 2>/dev/null || true
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
        aws events remove-targets --region "$REGION" --rule "$rule" --ids $target_ids 2>/dev/null || true
      fi
      echo "    Deleting EventBridge rule: $rule"
      aws events delete-rule --region "$REGION" --name "$rule" 2>/dev/null || true
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
    aws cloudwatch delete-alarms --region "$REGION" --alarm-names $alarm_names 2>/dev/null || true
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
      aws glue delete-trigger --region "$REGION" --name "$trig" 2>/dev/null || true
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
      aws glue delete-job --region "$REGION" --job-name "$job" 2>/dev/null || true
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
          aws sqs delete-queue --region "$REGION" --queue-url "$url" 2>/dev/null || true
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
            aws logs delete-log-group --region "$REGION" --log-group-name "$lg" 2>/dev/null || true
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
          aws glue delete-table --region "$REGION" --database-name "$db" --name "$table" 2>/dev/null || true
        fi
      done
      aws glue delete-database --region "$REGION" --name "$db" 2>/dev/null || true
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
    aws s3 rb "s3://$bucket" --force 2>/dev/null || true
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
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
    done
    for policy in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null); do
      echo "      Deleting inline policy: $policy"
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
    done
    aws iam delete-role --role-name "$role" 2>/dev/null || true
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
    aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
  fi
done

echo ""
echo "Cleanup completed!"
