# Integration Tests for terraform-federated-logs

### What We Test

| Category | Example |
|----------|---------|
| Input Validation | setup_name regex, reserved table names, cluster fields |
| Naming Conventions | S3, Glue DB, IAM role naming patterns |
| Module Wiring | Outputs from module A work as inputs to module B |
| Table Count Logic | Default table + custom tables = expected count |
| Update Scenarios | Add/remove clusters, add/remove tables |

## Prerequisites

- Terraform >= 1.6.0
- AWS credentials configured

---

## Running Tests

```bash
# Run all tests
terraform test

# Run specific test files
terraform test -filter=tests/setup_resource.tftest.hcl
terraform test -filter=tests/role.tftest.hcl
terraform test -filter=tests/partition.tftest.hcl
```

---

## Test Structure

```
tests/
├── setup_resource.tftest.hcl  # Tests for federated_logs_setup_resource
├── role.tftest.hcl            # Tests for federated_logs_role
├── partition.tftest.hcl       # Tests for federated_logs_partition
└── README.md
```

---

## Cleanup

To clean up orphaned test resources:

```bash
./scripts/cleanup-test-resources.sh
```

---

## CI/CD

Tests run automatically on every PR via GitHub Actions:

1. `pr-checks.yml` - Format, validate, lint, security scan (no AWS needed)
2. `integration-tests.yml` - Full integration tests (requires AWS credentials)
