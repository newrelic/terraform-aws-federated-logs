package integration

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFederatedLogsE2E(t *testing.T) {
	apiKey := requireEnv(t, "NEW_RELIC_API_KEY")
	licenseKey := requireEnv(t, "NEW_RELIC_LICENSE_KEY")
	accountIDStr := requireEnv(t, "NEW_RELIC_ACCOUNT_ID")
	fleetGUID := requireEnv(t, "TEST_FLEET_ENTITY_GUID")
	orgID := requireEnv(t, "TEST_NR_ORG_ID")

	accountID, err := strconv.Atoi(accountIDStr)
	require.NoErrorf(t, err, "NEW_RELIC_ACCOUNT_ID must be numeric, got %q", accountIDStr)

	runSuffix := randSuffix(t, 6)
	setupName := "inttest-e2e-setup-" + runSuffix // 24 chars; <= 26 limit
	dataProcName := "inttest-e2e-dp-" + runSuffix // 21 chars
	tablePrefix := "newrelic_fed_logs_" + strings.ReplaceAll(setupName, "-", "_") + "_"
	nrRegion := "US"
	awsRegion := "us-west-2" // matches the fixture default; pinned so the AWS CLI cleanup steps use the same region

	opts := &terraform.Options{
		TerraformDir: "fixtures/e2e",
		Vars: map[string]interface{}{
			"setup_name":           setupName,
			"data_processing_name": dataProcName,
			"fleet_entity_guid":    fleetGUID,
			"newrelic_org_id":      orgID,
			"newrelic_account_id":  accountID,
			"newrelic_region":      nrRegion,
			"aws_region":           awsRegion,
			"partition_tables":     map[string]interface{}{},
		},
		EnvVars: map[string]string{
			"NEW_RELIC_API_KEY":     apiKey,
			"NEW_RELIC_LICENSE_KEY": licenseKey,
			"AWS_REGION":            awsRegion,
		},
		NoColor: true,
	}

	defer teardown(t, opts)

	// ----- SCENARIO 1: default table only ------------------------------------
	t.Run("default_table_only", func(t *testing.T) {
		opts.Vars["partition_tables"] = map[string]interface{}{}

		terraform.InitAndApply(t, opts)

		tables := terraform.OutputMapOfObjects(t, opts, "all_tables")
		require.Lenf(t, tables, 1,
			"should have exactly 1 table (default) when no custom tables specified, got %d",
			len(tables))
	})

	// ----- VALIDATION: setup + AWS connection outputs -----------------------
	t.Run("validate_setup_and_aws_connection_outputs", func(t *testing.T) {
		bucketName := terraform.Output(t, opts, "s3_bucket_name")
		glueDBName := terraform.Output(t, opts, "glue_catalog_db_name")
		setupID := terraform.Output(t, opts, "setup_id")
		defaultPartitionID := terraform.Output(t, opts, "default_partition_id")
		awsConnID := terraform.Output(t, opts, "aws_connection_id")
		glueRoleARN := terraform.Output(t, opts, "glue_service_role_arn")

		// S3 bucket name: lowercase + digits + hyphens, embeds setup_name.
		bucketRe := regexp.MustCompile(`^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$`)
		assert.Regexpf(t, bucketRe, bucketName,
			"s3 bucket name %q doesn't match S3 naming rules", bucketName)
		assert.Containsf(t, bucketName, setupName,
			"s3 bucket name %q should embed setup_name %q", bucketName, setupName)

		// Glue catalog DB name: lowercase + underscores; setup_name's hyphens
		// become underscores.
		underscoredSetupName := strings.ReplaceAll(setupName, "-", "_")
		glueDBRe := regexp.MustCompile(`^[a-z0-9_]+$`)
		assert.Regexpf(t, glueDBRe, glueDBName,
			"glue db name %q should be lowercase + underscores only", glueDBName)
		assert.Containsf(t, glueDBName, underscoredSetupName,
			"glue db name %q should embed underscored setup_name %q",
			glueDBName, underscoredSetupName)

		// NR entity GUIDs: non-empty, and the three setup-side IDs must be distinct.
		assert.NotEmptyf(t, setupID, "setup_id should be non-empty")
		assert.NotEmptyf(t, defaultPartitionID, "default_partition_id should be non-empty")
		assert.NotEmptyf(t, awsConnID, "aws_connection_id should be non-empty")
		assert.NotEqualf(t, setupID, defaultPartitionID,
			"setup_id and default_partition_id must be distinct entities")
		assert.NotEqualf(t, setupID, awsConnID,
			"setup_id and aws_connection_id must be distinct entities")

		// Glue service role ARN
		iamRoleRe := regexp.MustCompile(`^arn:aws:iam::\d{12}:role/.+$`)
		assert.Regexpf(t, iamRoleRe, glueRoleARN,
			"glue_service_role_arn %q is not a valid IAM role ARN", glueRoleARN)
		assert.Containsf(t, glueRoleARN, setupName,
			"glue_service_role_arn %q should embed setup_name %q", glueRoleARN, setupName)

		customPartitionIDs := terraform.OutputMap(t, opts, "custom_partition_ids")
		assert.Emptyf(t, customPartitionIDs,
			"custom_partition_ids should be empty before any custom partitions are added, got %v",
			customPartitionIDs)
	})

	// ----- SCENARIO 2: add custom tables -------------------------------------
	t.Run("add_custom_tables", func(t *testing.T) {
		opts.Vars["partition_tables"] = map[string]interface{}{
			"app_logs":      map[string]interface{}{},
			"security_logs": map[string]interface{}{},
		}

		terraform.Apply(t, opts)

		tables := terraform.OutputMapOfObjects(t, opts, "all_tables")
		require.Lenf(t, tables, 3,
			"should have 3 tables (1 default + 2 custom), got %d", len(tables))

		// custom_partition_ids: one GUID per custom table, all non-empty.
		customPartitionIDs := terraform.OutputMap(t, opts, "custom_partition_ids")
		assert.Lenf(t, customPartitionIDs, 2,
			"custom_partition_ids should have 2 entries, got %d: %v",
			len(customPartitionIDs), customPartitionIDs)
		for k, v := range customPartitionIDs {
			assert.NotEmptyf(t, v, "custom partition %q should have a non-empty GUID", k)
		}
	})

	// ----- SCENARIO 3: table name sanitization -------------------------------
	t.Run("table_name_sanitization", func(t *testing.T) {
		opts.Vars["partition_tables"] = map[string]interface{}{
			"app_logs":       map[string]interface{}{},
			"security_logs":  map[string]interface{}{},
			"My-App.Logs":    map[string]interface{}{}, // hyphen + dot
			"UPPERCASE_NAME": map[string]interface{}{}, // uppercase
		}

		terraform.Apply(t, opts)

		tables := terraform.OutputMapOfObjects(t, opts, "all_tables")
		require.Lenf(t, tables, 5, "should have 5 tables (1 default + 4 custom), got %d", len(tables))

		nameRe := regexp.MustCompile(`^[a-z0-9_]+$`)
		for name := range tables {
			assert.Regexpf(t, nameRe, name,
				"table name %q should be lowercase alphanumeric + underscores only", name)
			assert.Truef(t, strings.HasPrefix(name, tablePrefix),
				"table name %q should start with prefix %q", name, tablePrefix)
		}
	})

	// ----- SCENARIO 4: custom optimizer config -------------------------------
	t.Run("custom_optimizer_config", func(t *testing.T) {
		opts.Vars["partition_tables"] = map[string]interface{}{
			"app_logs":       map[string]interface{}{},
			"security_logs":  map[string]interface{}{},
			"My-App.Logs":    map[string]interface{}{},
			"UPPERCASE_NAME": map[string]interface{}{},
			"custom_config_table": map[string]interface{}{
				"table_parameters": map[string]interface{}{
					"custom_param": "custom_value",
				},
				"optimizer_configuration": map[string]interface{}{
					"orphan_file_deletion": map[string]interface{}{
						"orphan_file_retention_period_in_days": 7,
						"run_rate_in_hours":                    12,
					},
					"snapshot_retention": map[string]interface{}{
						"snapshot_retention_period_in_days": 10,
						"number_of_snapshots_to_retain":     5,
						"clean_expired_files":               true,
						"run_rate_in_hours":                 12,
					},
				},
			},
		}

		terraform.Apply(t, opts)

		tables := terraform.OutputMapOfObjects(t, opts, "all_tables")
		require.Lenf(t, tables, 6, "should have 6 tables (1 default + 5 custom), got %d", len(tables))

		// custom_partition_ids: 5 GUIDs, all non-empty.
		customPartitionIDs := terraform.OutputMap(t, opts, "custom_partition_ids")
		assert.Lenf(t, customPartitionIDs, 5,
			"custom_partition_ids should have 5 entries, got %d", len(customPartitionIDs))
		for k, v := range customPartitionIDs {
			assert.NotEmptyf(t, v, "custom partition %q should have a non-empty GUID", k)
		}
	})

	// ----- SCENARIO 5: removal blocked by prevent_destroy --------------------
	t.Run("removal_blocked", func(t *testing.T) {
		opts.Vars["partition_tables"] = map[string]interface{}{
			"app_logs":      map[string]interface{}{},
			"security_logs": map[string]interface{}{},
		}

		_, err := terraform.ApplyE(t, opts)
		require.Errorf(t, err,
			"apply should fail because removing partition tables hits prevent_destroy")
		assert.Containsf(t, err.Error(), "Instance cannot be destroyed",
			"error should mention prevent_destroy violation, got: %s", err.Error())
	})

	// ----- SCENARIO 6: custom default table setting --------------------------
	t.Run("custom_default_table_setting", func(t *testing.T) {
		opts.Vars["partition_tables"] = map[string]interface{}{
			"app_logs":            map[string]interface{}{},
			"security_logs":       map[string]interface{}{},
			"My-App.Logs":         map[string]interface{}{},
			"UPPERCASE_NAME":      map[string]interface{}{},
			"custom_config_table": map[string]interface{}{},
		}
		opts.Vars["default_table_setting"] = map[string]interface{}{
			"table_parameters": map[string]interface{}{
				"default_custom_param": "default_custom_value",
			},
		}

		terraform.Apply(t, opts)

		tables := terraform.OutputMapOfObjects(t, opts, "all_tables")
		require.Lenf(t, tables, 6,
			"should have 6 tables (1 customized default + 5 carried-forward custom), got %d",
			len(tables))
	})

	// ----- SCENARIO 7: resource removed blocks -------
	t.Run("decommission_via_removed_blocks", func(t *testing.T) {
		mainTfPath := filepath.Join(opts.TerraformDir, "main.tf")
		outputsTfPath := filepath.Join(opts.TerraformDir, "outputs.tf")

		originalMain, err := os.ReadFile(mainTfPath)
		require.NoError(t, err)
		originalOutputs, err := os.ReadFile(outputsTfPath)
		require.NoError(t, err)
		t.Cleanup(func() {
			_ = os.WriteFile(mainTfPath, originalMain, 0644)
			_ = os.WriteFile(outputsTfPath, originalOutputs, 0644)
		})

		decommissionTf := `removed {
		  from = module.setup.aws_s3_bucket.this
		  lifecycle { destroy = false }
		}

		removed {
		  from = module.setup.aws_glue_catalog_database.this
		  lifecycle { destroy = false }
		}

		removed {
		  from = module.partition.aws_s3_object.folder
		  lifecycle { destroy = false }
		}

		removed {
		  from = module.partition.aws_glue_catalog_table.iceberg_table
		  lifecycle { destroy = false }
		}
		`
		require.NoError(t, os.WriteFile(mainTfPath, []byte(decommissionTf), 0644))
		require.NoError(t, os.WriteFile(outputsTfPath, []byte(""), 0644))

		planArgs := terraform.FormatArgs(opts, "plan", "-no-color", "-input=false", "-lock=false")
		out, err := terraform.RunTerraformCommandE(t, opts, planArgs...)
		require.NoErrorf(t, err,
			"terraform plan with whole-resource removed blocks should succeed; got:\n%s", out)

		assert.NotContainsf(t, out, "Instance cannot be destroyed",
			"plan should not hit prevent_destroy when removed blocks are used, got:\n%s", out)

		for _, addr := range []string{
			"aws_s3_bucket.this",
			"aws_glue_catalog_database.this",
			"aws_s3_object.folder",
			"aws_glue_catalog_table.iceberg_table",
		} {
			assert.Containsf(t, out, addr,
				"plan should reference %s as part of the decommission, got:\n%s", addr, out)
		}
	})

	// ----- SCENARIO 8: destroy blocked by prevent_destroy ------------------
	t.Run("destroy_blocked", func(t *testing.T) {
		_, err := terraform.DestroyE(t, opts)
		require.Errorf(t, err,
			"terraform destroy should fail because storage resources have prevent_destroy")

		assert.Containsf(t, err.Error(), "Instance cannot be destroyed",
			"destroy error should mention prevent_destroy violation, got: %s", err.Error())
	})
}

func teardown(t *testing.T, opts *terraform.Options) {
	for _, addr := range storageStateAddresses(t, opts) {
		t.Logf("teardown: state rm %s", addr)
		if _, err := terraform.RunTerraformCommandE(t, opts, "state", "rm", addr); err != nil {
			t.Logf("teardown: state rm %s failed: %v", addr, err)
		}
	}

	destroyArgs := terraform.FormatArgs(opts, "destroy", "-auto-approve", "-input=false", "-refresh=false")
	if _, err := terraform.RunTerraformCommandE(t, opts, destroyArgs...); err != nil {
		t.Logf("teardown: terraform destroy failed: %v", err)
	}
}

func storageStateAddresses(t *testing.T, opts *terraform.Options) []string {
	out, err := terraform.RunTerraformCommandE(t, opts, "state", "list")
	if err != nil {
		t.Logf("teardown: terraform state list failed: %v", err)
		return nil
	}

	var addrs []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasSuffix(line, ".aws_s3_bucket.this"),
			strings.HasSuffix(line, ".aws_glue_catalog_database.this"),
			strings.Contains(line, ".aws_s3_object.folder["),
			strings.Contains(line, ".aws_glue_catalog_table.iceberg_table["):
			addrs = append(addrs, line)
		}
	}
	return addrs
}

func requireEnv(t *testing.T, name string) string {
	v := os.Getenv(name)
	require.NotEmptyf(t, v, "%s must be set (see package doc for required env vars)", name)
	return v
}

func randSuffix(t *testing.T, n int) string {
	b := make([]byte, (n+1)/2)
	_, err := rand.Read(b)
	require.NoError(t, err)
	return hex.EncodeToString(b)[:n]
}
