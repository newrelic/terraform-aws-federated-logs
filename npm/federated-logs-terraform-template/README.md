# @shared-package/federated-logs-terraform-template

Terraform template package for Federated Logs UI.

## Purpose

This package exports the root Terraform configuration (`main.tf`) as a JavaScript constant for consumption by the Federated Logs UI component.

## Source of Truth

- **Template source**: Repository root `main.tf`
- **Generated output**: `index.js`

## How It Works

1. The `generate.js` script reads `../../main.tf`
2. Replaces `var.setup_name` with the placeholder `__SETUP_NAME__`
3. Exports as JavaScript constants in `index.js`

## Publishing

This package is automatically published via GitHub Actions when:
- `main.tf` changes in the repository
- Changes are pushed to the `master` branch

**Workflow**: `.github/workflows/publish-terraform-template-package.yml`

## Exports

```javascript
module.exports = {
  FEDERATED_LOGS_TF_TEMPLATE,           // The Terraform template string
  FEDERATED_LOGS_TF_PLACEHOLDER_SETUP_NAME,  // "__SETUP_NAME__"
  FEDERATED_LOGS_TF_VERSION,            // Package version
};
```

## Usage in UI Component

```javascript
import {
  FEDERATED_LOGS_TF_TEMPLATE,
  FEDERATED_LOGS_TF_PLACEHOLDER_SETUP_NAME,
} from '@shared-package/federated-logs-terraform-template';

function buildTerraformSnippet(setupName) {
  return FEDERATED_LOGS_TF_TEMPLATE.replace(
    FEDERATED_LOGS_TF_PLACEHOLDER_SETUP_NAME,
    setupName || '<SETUP_NAME>'
  );
}
```

## Manual Generation

To manually regenerate `index.js` from `main.tf`:

```bash
cd npm/federated-logs-terraform-template
npm run generate
```

## Version Updates

To publish a new version:

1. Update `version` in `package.json`
2. Push changes to `master`
3. GitHub Actions will publish automatically

## Registry

Published to: `https://artifacts.datanerd.us/artifactory/api/npm/newrelic-js-local/`
