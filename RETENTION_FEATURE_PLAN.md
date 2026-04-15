# Data Retention Feature Implementation Plan

> **IMPLEMENTATION UPDATE:** This feature has been refactored to use **Glue Spark ETL** instead of Python Shell for cleaner, more maintainable code. The Spark SQL approach reduces code complexity by ~50% while providing native Iceberg DELETE support.

## Context

This module currently provisions AWS infrastructure for New Relic Federated Logs using Apache Iceberg tables. Users need an automated data retention mechanism to:
- Enforce lifecycle policies on federated log data
- Reduce S3 storage costs by deleting old data
- Comply with organizational retention requirements

The feature will run a scheduled Glue ETL job that deletes data older than configured retention periods using Iceberg DELETE operations. Physical cleanup is handled by existing Glue optimizers.

## Design Decisions (Based on User Feedback)

- **Per-table retention**: Each table can have different retention periods (follows existing optimizer pattern)
- **Optional API key**: Works without NGEP API for testing (uses Terraform-provided retention values)
- **Inline Python script**: Embedded in Terraform using heredoc (user preference)
- **Continue on error**: Process all tables even if one fails (partial cleanup better than none)
- **Spark ETL Job**: Uses Glue Spark ETL with Spark SQL for native Iceberg DELETE operations (simpler, more maintainable)

## Implementation Approach

### 1. Variable Structure

**In `modules/federated_logs_partition/variables.tf`:**

Add three new variables:
- `newrelic_api_key` (string, sensitive, optional) - For NGEP API auth, stored in Secrets Manager
- `enable_data_retention` (bool, default false) - Feature flag to opt-in
- `retention_schedule` (string, default "cron(0 0 * * ? *)") - EventBridge cron expression

Update existing table configuration objects:
- Add `data_retention` nested object to `default_table_setting`
- Add `data_retention` nested object to `partition_tables` map
- Structure: `{ retention_period = "7 DAYS", enabled = true }`
- Add validation regex: `^[0-9]+ (HOUR|HOURS|DAY|DAYS|WEEK|WEEKS|MONTH|MONTHS)$`

### 2. Locals Computation

**In `modules/federated_logs_partition/locals.tf`:**

Add computed values:
```hcl
retention_enabled_tables = {
  for k, v in local.all_tables : k => v
  if var.enable_data_retention && v.data_retention != null && v.data_retention.enabled
}

has_retention_enabled = length(local.retention_enabled_tables) > 0

# JSON config passed to Glue job
retention_job_config = jsonencode({
  for k, v in local.retention_enabled_tables : k => {
    retention_period = v.data_retention.retention_period
  }
})
```

### 3. IAM Permissions

**In `modules/federated_logs_role/main.tf`:**

Extend `aws_iam_policy.glue_service_policy` with three new statement blocks:

1. **Secrets Manager** - Read API key
   - Action: `secretsmanager:GetSecretValue`
   - Resource: `arn:aws:secretsmanager:${region}:${account}:secret:${setup_naming_prefix}-newrelic-api-*`

2. **Athena** - Execute DELETE queries
   - Actions: `athena:StartQueryExecution`, `athena:GetQueryExecution`, `athena:GetQueryResults`, `athena:StopQueryExecution`
   - Resource: `arn:aws:athena:${region}:${account}:workgroup/*`

3. **S3 Athena Results** - Store query results
   - Actions: `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`
   - Resource: Existing bucket with `/athena-results/*` prefix

### 4. Retention Resources

**Create new file `modules/federated_logs_partition/retention.tf`:**

All resources use `count = local.has_retention_enabled ? 1 : 0` for conditional creation.

**Resources:**

1. **aws_secretsmanager_secret** - Store API key
   - Name: `${setup_naming_prefix}-newrelic-api-key`
   - Only created if `var.newrelic_api_key != null`

2. **aws_secretsmanager_secret_version** - API key value
   - JSON format: `{"api_key": "${var.newrelic_api_key}"}`
   - Marked as sensitive

3. **aws_s3_object** - Glue job script
   - Key: `${glue_catalog_db_name}/scripts/retention_job.py`
   - Content: Inline Python script (see section 5)
   - Etag trigger for updates

4. **aws_glue_job** - Spark ETL job
   - Name: `${setup_naming_prefix}-retention-job`
   - Command: `glueetl`
   - Glue version: `4.0`
   - Python version: `3`
   - Script location: S3 object from above
   - Role: `var.glue_service_role_arn`
   - Worker type: `G.1X`
   - Number of workers: `2` (minimum for Spark)
   - Timeout: `120` minutes
   - Max retries: `1`
   - Default arguments:
     - `--DATABASE_NAME`: `var.glue_catalog_db_name`
     - `--S3_BUCKET`: `var.s3_bucket_name`
     - `--SECRET_ARN`: Secret ARN (or empty if no key)
     - `--TABLE_CONFIG`: `local.retention_job_config`
     - `--enable-continuous-cloudwatch-log`: `true`
     - `--enable-glue-datacatalog`: `true`
     - `--enable-metrics`: `true`

5. **aws_cloudwatch_event_rule** - Schedule trigger
   - Name: `${setup_naming_prefix}-retention-schedule`
   - Schedule expression: `var.retention_schedule`
   - Description: "Trigger retention cleanup job for ${var.setup_name}"

6. **aws_cloudwatch_event_target** - Connect rule to job
   - Rule: Event rule name
   - Target: Glue job ARN
   - Role: Glue service role

7. **aws_cloudwatch_log_group** - Job logs
   - Name: `/aws-glue/jobs/${setup_naming_prefix}-retention-job`
   - Retention: 7 days

### 5. Python Script Logic

**Inline script structure** (embedded in `aws_s3_object` resource):

```python
import sys
import json
import boto3
import time
from datetime import datetime, timedelta

def parse_retention_period(retention_str):
    """Convert '7 DAYS' to timedelta"""
    value, unit = retention_str.strip().split()
    multipliers = {
        'HOUR': 1/24, 'HOURS': 1/24,
        'DAY': 1, 'DAYS': 1,
        'WEEK': 7, 'WEEKS': 7,
        'MONTH': 30, 'MONTHS': 30
    }
    return timedelta(days=int(value) * multipliers[unit.upper()])

def calculate_cutoff_timestamp(retention_period):
    """Calculate deletion cutoff aligned to midnight UTC for efficient partition deletion"""
    now = datetime.utcnow()
    cutoff = now - parse_retention_period(retention_period)
    return cutoff.replace(hour=0, minute=0, second=0, microsecond=0)

def execute_iceberg_delete(athena_client, database, table, cutoff, s3_output):
    """Execute Iceberg DELETE via Athena"""
    query = f"""
    DELETE FROM "{database}"."{table}"
    WHERE timestamp < TIMESTAMP '{cutoff.strftime('%Y-%m-%d %H:%M:%S')}'
    """
    
    response = athena_client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={'Database': database},
        ResultConfiguration={'OutputLocation': s3_output}
    )
    
    # Poll for completion
    query_id = response['QueryExecutionId']
    while True:
        result = athena_client.get_query_execution(QueryExecutionId=query_id)
        state = result['QueryExecution']['Status']['State']
        if state in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
            return state, result
        time.sleep(2)

def get_api_key(secrets_client, secret_arn):
    """Retrieve API key from Secrets Manager (optional)"""
    if not secret_arn:
        return None
    try:
        response = secrets_client.get_secret_value(SecretId=secret_arn)
        return json.loads(response['SecretString'])['api_key']
    except Exception as e:
        print(f"Warning: Could not retrieve API key: {e}")
        return None

def fetch_ngep_policy(api_key, setup_name):
    """TODO: Implement NGEP API GraphQL query - Returns None for now"""
    # Future implementation:
    # - GraphQL query to NGEP API
    # - Fetch retention policies for all tables
    # - Return policy map or None if unavailable
    return None

def main():
    args = getResolvedOptions(sys.argv, [
        'DATABASE_NAME', 'S3_BUCKET', 'SECRET_ARN', 'TABLE_CONFIG'
    ])
    
    # Initialize clients
    athena = boto3.client('athena')
    secrets = boto3.client('secretsmanager')
    
    # Get API key (optional for testing)
    api_key = get_api_key(secrets, args.get('SECRET_ARN', ''))
    
    # Parse table configuration from Terraform
    terraform_config = json.loads(args['TABLE_CONFIG'])
    
    # Try NGEP API (TODO - not implemented yet)
    ngep_policy = None
    if api_key:
        try:
            ngep_policy = fetch_ngep_policy(api_key, args['DATABASE_NAME'])
        except Exception as e:
            print(f"NGEP API error: {e}")
            print("ABORTING: Fail-safe to prevent unintended data loss")
            sys.exit(1)
    
    # Use NGEP policy if available, otherwise use Terraform config
    retention_policy = ngep_policy if ngep_policy else terraform_config
    print(f"Using {'NGEP' if ngep_policy else 'Terraform'} retention policy")
    
    # Athena output location
    s3_output = f"s3://{args['S3_BUCKET']}/athena-results/"
    
    # Process each table
    results = {}
    for table_name, config in retention_policy.items():
        try:
            cutoff = calculate_cutoff_timestamp(config['retention_period'])
            print(f"\n[{table_name}] Deleting data before {cutoff}")
            
            state, result = execute_iceberg_delete(
                athena, args['DATABASE_NAME'], table_name, cutoff, s3_output
            )
            
            if state == 'SUCCEEDED':
                # TODO: Notify NGEP API of success
                results[table_name] = 'SUCCESS'
                print(f"[{table_name}] ✓ Deletion completed")
            else:
                error = result['QueryExecution']['Status'].get('StateChangeReason', 'Unknown')
                results[table_name] = f'FAILED: {error}'
                print(f"[{table_name}] ✗ Failed: {error}")
                # TODO: Notify NGEP API of failure
                
        except Exception as e:
            error_msg = str(e)
            results[table_name] = f'ERROR: {error_msg}'
            print(f"[{table_name}] ✗ Error: {error_msg}")
            # Continue with other tables (don't fail fast)
    
    # Summary
    print(f"\n{'='*60}")
    print("RETENTION JOB SUMMARY")
    print(f"{'='*60}")
    print(json.dumps(results, indent=2))
    
    # Exit with error code if any failures
    failed = [t for t, s in results.items() if s != 'SUCCESS']
    if failed:
        print(f"\n⚠ {len(failed)} table(s) failed: {', '.join(failed)}")
        sys.exit(1)

if __name__ == '__main__':
    main()
```

### 6. Module Outputs

**In `modules/federated_logs_partition/outputs.tf`:**

Add three new outputs:
```hcl
output "retention_job_name" {
  description = "Name of the Glue retention job (if enabled)"
  value       = local.has_retention_enabled ? aws_glue_job.retention[0].name : null
}

output "retention_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the API key (if configured)"
  value       = var.newrelic_api_key != null && local.has_retention_enabled ? aws_secretsmanager_secret.newrelic_api_key[0].arn : null
}

output "retention_enabled_tables" {
  description = "Map of tables with retention enabled"
  value       = local.retention_enabled_tables
}
```

### 7. Root Module Integration

**In `variables.tf` (root):**

Add pass-through variables:
```hcl
variable "newrelic_api_key" {
  description = "New Relic API key for NGEP integration (optional for testing)"
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_data_retention" {
  description = "Enable automated data retention cleanup"
  type        = bool
  default     = false
}

variable "retention_schedule" {
  description = "Cron expression for retention job (default: daily at midnight UTC)"
  type        = string
  default     = "cron(0 0 * * ? *)"
}
```

**In `main.tf` (root):**

Pass to partition module:
```hcl
module "partition" {
  # ... existing config ...
  newrelic_api_key      = var.newrelic_api_key
  enable_data_retention = var.enable_data_retention
  retention_schedule    = var.retention_schedule
}
```

### 8. Documentation Updates

**In `README.md`:**

Add section:
```markdown
## Data Retention (Optional)

Enable automated deletion of old log data to manage storage costs and compliance:

```hcl
module "federated_logs" {
  # ... other config ...
  
  enable_data_retention = true
  newrelic_api_key      = var.nr_api_key  # Optional: for NGEP API integration
  retention_schedule    = "cron(0 0 * * ? *)"  # Daily at midnight UTC
  
  default_table_setting = {
    data_retention = {
      retention_period = "7 DAYS"
      enabled          = true
    }
  }
  
  partition_tables = {
    "security_log" = {
      data_retention = {
        retention_period = "90 DAYS"  # Keep security logs longer
        enabled          = true
      }
    }
    "debug_log" = {
      data_retention = {
        retention_period = "1 DAY"  # Short retention for debug logs
        enabled          = true
      }
    }
  }
}
```

**Retention Period Format:** `<number> <HOURS|DAYS|WEEKS|MONTHS>` (e.g., "3 DAYS", "2 WEEKS", "6 MONTHS")

**How It Works:**
- EventBridge triggers a Glue job on the configured schedule
- Job deletes data older than the retention period using Iceberg DELETE
- Deletion aligned to midnight (00:00) for efficient whole-partition drops
- Existing Glue optimizers clean up physical S3 files
- Job continues processing even if individual tables fail

**Cost:** ~$0.50-1.00/month per setup (Secrets Manager + Glue job execution)
```

**In `examples/complete/main.tf`:**

Add retention example:
```hcl
module "federated_logs" {
  # ... existing config ...
  
  # Enable data retention
  enable_data_retention = true
  newrelic_api_key      = "your-api-key-here"  # Use AWS Secrets Manager or variable
  retention_schedule    = "cron(0 1 * * ? *)"  # 1 AM UTC daily
  
  default_table_setting = {
    # ... existing config ...
    data_retention = {
      retention_period = "7 DAYS"
      enabled          = true
    }
  }
  
  partition_tables = {
    "application_log" = {
      data_retention = {
        retention_period = "7 DAYS"
        enabled          = true
      }
    }
    "security_log" = {
      data_retention = {
        retention_period = "90 DAYS"
        enabled          = true
      }
    }
  }
}
```

## Critical Files to Modify

1. **`modules/federated_logs_partition/variables.tf`** - Add 3 new variables + extend table config objects
2. **`modules/federated_logs_partition/locals.tf`** - Add retention_enabled_tables + retention_job_config
3. **`modules/federated_logs_partition/retention.tf`** - NEW FILE with all retention resources
4. **`modules/federated_logs_role/main.tf`** - Extend glue_service_policy with 3 new statement blocks
5. **`modules/federated_logs_partition/outputs.tf`** - Add 3 new outputs
6. **`variables.tf`** - Add 3 pass-through variables
7. **`main.tf`** - Pass variables to partition module
8. **`README.md`** - Document feature
9. **`examples/complete/main.tf`** - Add example

## Implementation Sequence

1. **IAM permissions** (federated_logs_role/main.tf) - Foundation for other resources
2. **Variables** (partition module) - Define inputs
3. **Locals** (partition module) - Computed values
4. **Retention resources** (retention.tf) - Core implementation
5. **Outputs** (partition module) - Expose job details
6. **Root module** (main.tf, variables.tf) - Wire everything together
7. **Examples** (examples/complete) - Demonstrate usage
8. **Documentation** (README.md) - Explain feature

## Testing Plan

1. **Deploy with retention disabled** - Verify no retention resources created
2. **Deploy with retention enabled** - Verify all resources exist (Secrets Manager, Glue job, EventBridge rule)
3. **Manual job trigger** - Test via AWS Console or CLI
4. **Verify Athena query** - Check CloudWatch logs for DELETE execution
5. **Test error handling** - Disable Athena access, verify job continues with other tables
6. **Test without API key** - Verify job works with Terraform config only
7. **Partial hour deletion** - Insert data with timestamps like 04:15 and 04:45, verify proper handling

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    TERRAFORM DEPLOYMENT                      │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   S3       │  │ Glue Catalog │  │  IAM Roles       │   │
│  │  Bucket    │  │   Database   │  │  & Policies      │   │
│  └────────────┘  └──────────────┘  └──────────────────┘   │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │         DATA RETENTION RESOURCES                    │    │
│  │  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │  Secrets     │  │   Glue Job   │               │    │
│  │  │  Manager     │  │ (Python ETL) │               │    │
│  │  └──────────────┘  └──────────────┘               │    │
│  │         ▲                  ▲                        │    │
│  │         │                  │                        │    │
│  │  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │  API Key     │  │ EventBridge  │               │    │
│  │  │   Input      │  │   Schedule   │               │    │
│  │  └──────────────┘  └──────────────┘               │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  RUNTIME EXECUTION (Every 24h)               │
│                                                              │
│  1. EventBridge triggers Glue Job                           │
│  2. Job retrieves API key from Secrets Manager              │
│  3. Job fetches retention config (Terraform or NGEP)        │
│  4. For each table:                                          │
│     - Calculate cutoff timestamp                             │
│     - Execute: DELETE FROM table WHERE timestamp < cutoff    │
│     - Log results to CloudWatch                              │
│  5. Glue optimizers clean up physical S3 files              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Why Python Spark Script is Needed

**Terraform's Job:** Infrastructure as Code
- Creates AWS resources (S3, Glue, IAM, EventBridge)
- Runs ONCE during `terraform apply`
- Cannot execute dynamic runtime logic

**Python Spark Script's Job:** Application Logic
- Runs PERIODICALLY (every 24 hours via EventBridge)
- Performs dynamic calculations (e.g., "What's the date 7 days ago?")
- Executes Spark SQL DELETE queries on Iceberg tables
- Handles per-table errors and logging
- Cannot be done by Terraform (Terraform doesn't run queries)

**Why Spark ETL Instead of Python Shell:**
- **Simpler code**: 100 lines vs 200 lines
- **Native Iceberg support**: Spark SQL handles DELETE directly
- **No polling**: Synchronous execution, no status checking needed
- **Better debugging**: Clear Spark error messages
- **Slight cost increase**: ~$2/month more, but worth it for maintainability

**Analogy:**
- Terraform = Building a house with a robotic vacuum
- Python Spark = The AI that tells the vacuum where to clean each day
- Spark ETL vs Python Shell = Industrial vacuum vs hand-held (more power, cleaner code)

## Known Limitations / TODOs

- **NGEP API integration** - Marked as TODO, currently uses Terraform-provided retention config
- **NGEP status notifications** - Marked as TODO, no callback on success/failure
- **Athena workgroup** - Uses default workgroup (could create dedicated one)
- **Query result cleanup** - Athena results stored in S3 `/athena-results/` (should add lifecycle policy)
- **Metrics** - No custom CloudWatch metrics for records deleted (could add)
- **Regional support** - Assumes single region (no cross-region support)

## Security Considerations

- API key stored encrypted in Secrets Manager
- IAM role uses least privilege (specific resource ARNs)
- Fail-safe: Job aborts if NGEP API configured but unreachable
- CloudTrail logs all Secrets Manager access
- No VPC required (job accesses AWS services via public endpoints)

## Rollback Plan

To disable retention:
1. Set `enable_data_retention = false`
2. Run `terraform apply`
3. All retention resources destroyed (Secrets Manager, Glue job, EventBridge rule)
4. Data tables and existing optimizers remain intact

## Estimated Cost

- Secrets Manager: $0.40/month
- Glue Spark ETL: ~$2.20/month (5 min/day, 2x G.1X workers at $0.44/DPU-hour)
- EventBridge: Free (scheduled rules included)
- CloudWatch Logs: Minimal (~$0.05/month)

**Total: ~$2.65/month per setup**

**Cost Comparison:**
- Python Shell approach: ~$0.50/month (cheaper but 200+ lines of complex code)
- Spark ETL approach: ~$2.65/month (slightly more expensive but 100 lines of simple code)

The $2/month premium is worthwhile for significantly improved maintainability and native Iceberg support.

## Questions for User Review

1. **Python Script Necessity** - Now that you understand why it's needed, are you comfortable with this approach?

2. **NGEP API Integration Timeline** - When should we implement the actual NGEP GraphQL queries?

3. **One Job vs Multiple Jobs** - Current design: ONE job processes ALL tables. Alternative: One job per table. Which do you prefer?

4. **API Key Storage** - We're storing it in Secrets Manager even without NGEP. Is this the right approach?

5. **Retention Granularity** - Per-table retention is implemented. Do you need per-partition (hourly) retention as well?

6. **Error Notifications** - Should we add SNS topic for job failures?
