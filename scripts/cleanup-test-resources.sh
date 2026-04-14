#!/bin/bash
# Cleanup script for orphaned test resources
# This script removes any resources created by integration tests that weren't properly cleaned up

set -e

# S3 buckets use hyphens: newrelic-fed-logs-inttest-*
# Glue DBs use underscores: newrelic_fed_logs_inttest_*
PREFIX_HYPHEN="inttest-"
PREFIX_UNDERSCORE="inttest_"
REGION="${AWS_REGION:-us-east-1}"

echo "Cleaning up test resources..."
echo "AWS Region: $REGION"

# Delete test S3 buckets (use hyphen prefix)
echo "Deleting test S3 buckets..."
aws s3api list-buckets --query "Buckets[?starts_with(Name, 'newrelic-fed-logs-${PREFIX_HYPHEN}')].Name" --output text 2>/dev/null | \
while read -r bucket; do
  if [ -n "$bucket" ]; then
    echo "  Deleting bucket: $bucket"
    aws s3 rb "s3://$bucket" --force 2>/dev/null || true
  fi
done

# Delete test Glue databases (use underscore prefix)
echo "Deleting test Glue databases..."
aws glue get-databases --region "$REGION" --query "DatabaseList[?starts_with(Name, 'newrelic_fed_logs_${PREFIX_UNDERSCORE}')].Name" --output text 2>/dev/null | \
while read -r db; do
  if [ -n "$db" ]; then
    echo "  Deleting Glue database: $db"
    # First delete all tables in the database
    aws glue get-tables --region "$REGION" --database-name "$db" --query 'TableList[].Name' --output text 2>/dev/null | \
    while read -r table; do
      if [ -n "$table" ]; then
        echo "    Deleting table: $table"
        aws glue delete-table --region "$REGION" --database-name "$db" --name "$table" 2>/dev/null || true
      fi
    done
    aws glue delete-database --region "$REGION" --name "$db" 2>/dev/null || true
  fi
done

# Delete test IAM roles (use hyphen prefix)
echo "Deleting test IAM roles..."
aws iam list-roles --query "Roles[?starts_with(RoleName, 'newrelic-fed-logs-${PREFIX_HYPHEN}')].RoleName" --output text 2>/dev/null | \
while read -r role; do
  if [ -n "$role" ]; then
    echo "  Deleting IAM role: $role"
    # Detach managed policies
    for policy in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
      echo "    Detaching policy: $policy"
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
    done
    # Delete inline policies
    for policy in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null); do
      echo "    Deleting inline policy: $policy"
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
    done
    aws iam delete-role --role-name "$role" 2>/dev/null || true
  fi
done

# Delete test IAM policies (use hyphen prefix)
echo "Deleting test IAM policies..."
aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName, 'newrelic-fed-logs-${PREFIX_HYPHEN}')].Arn" --output text 2>/dev/null | \
while read -r policy_arn; do
  if [ -n "$policy_arn" ]; then
    echo "  Deleting IAM policy: $policy_arn"
    aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
  fi
done

echo "Cleanup completed!"
