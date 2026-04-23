const fs = require('fs');
const path = require('path');

// Configuration
const PLACEHOLDER = '__SETUP_NAME__';
const MAIN_TF_PATH = path.resolve(__dirname, '..', '..', 'main.tf');
const OUTPUT_PATH = path.join(__dirname, 'index.js');

// Read package version
const { version } = require('./package.json');

// Read and transform main.tf
const template = fs.readFileSync(MAIN_TF_PATH, 'utf8')
  .replace(/setup_name\s*=\s*var\.setup_name/g, `setup_name = "${PLACEHOLDER}"`)
  .trim();

// Generate index.js
const output = `// Auto-generated from main.tf - DO NOT EDIT MANUALLY
// Generated on: ${new Date().toISOString()}
// Version: ${version}

const FEDERATED_LOGS_TF_TEMPLATE = ${JSON.stringify(template)};
const FEDERATED_LOGS_TF_PLACEHOLDER_SETUP_NAME = "${PLACEHOLDER}";
const FEDERATED_LOGS_TF_VERSION = "${version}";

module.exports = {
  FEDERATED_LOGS_TF_TEMPLATE,
  FEDERATED_LOGS_TF_PLACEHOLDER_SETUP_NAME,
  FEDERATED_LOGS_TF_VERSION,
};
`;

// Write output
fs.writeFileSync(OUTPUT_PATH, output, 'utf8');

console.log('✅ Generated index.js successfully');
console.log(`   Version: ${version}`);
console.log(`   Placeholder: ${PLACEHOLDER}`);
console.log(`   Template size: ${template.length} characters`);
