import sys
import json
from datetime import datetime, timedelta, timezone
from pyspark.sql import SparkSession
from awsglue.utils import getResolvedOptions

def main():
    # Parse job parameters
    args = getResolvedOptions(sys.argv, ['DATABASE_NAME', 'TABLE_RETENTION'])
    database = args['DATABASE_NAME']
    table_retention_json = args['TABLE_RETENTION']

    # Parse JSON map of table names to retention days
    table_retention = json.loads(table_retention_json)

    # Initialize Spark session
    spark = SparkSession.builder \
        .appName("FederatedLogsRetention") \
        .getOrCreate()

    # Process each table with its specific retention period
    results = {}
    for table_name, retention_days in table_retention.items():
        print(f"Processing table: {table_name}")
        print(f"Retention period: {retention_days} days")

        # Calculate cutoff timestamp aligned to midnight UTC for efficient partition deletion
        now = datetime.now(timezone.utc)
        cutoff = (now - timedelta(days=retention_days)).replace(hour=0, minute=0, second=0, microsecond=0)
        cutoff_str = cutoff.strftime('%Y-%m-%d %H:%M:%S')
        print(f"Cutoff timestamp (midnight-aligned): {cutoff_str}")

        try:
            # Execute DELETE using Spark SQL with Iceberg catalog
            delete_query = f"DELETE FROM glue_catalog.{database}.{table_name} WHERE timestamp < TIMESTAMP '{cutoff_str}'"
            print(f"[{table_name}] Executing: {delete_query}")
            spark.sql(delete_query)

            results[table_name] = 'SUCCESS'
            print(f"[{table_name}] Deletion completed successfully")

        except Exception as e:
            error_msg = str(e)
            results[table_name] = f'ERROR: {error_msg}'
            print(f"[{table_name}] Error: {error_msg}")

            # Continue with other tables (don't fail fast)
            continue

    # Stop Spark session
    spark.stop()

    # Exit with error code if any failures
    failed = [t for t, s in results.items() if s != 'SUCCESS']
    if failed:
        print(f"{len(failed)} table(s) failed: {', '.join(failed)}")
        sys.exit(1)
    else:
        print(f"All {len(results)} table(s) processed successfully")


if __name__ == '__main__':
    main()
