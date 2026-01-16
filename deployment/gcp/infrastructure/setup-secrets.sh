#!/bin/bash
# Setup all n8n secrets in Google Cloud Secret Manager
# This script creates secrets for all environment variables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/project-config.sh"
source "${SCRIPT_DIR}/../config/env-vars.sh"

echo "=========================================="
echo "Setting up n8n secrets in Secret Manager"
echo "=========================================="
echo "Project: ${GCP_PROJECT}"
echo "Secret prefix: ${SECRET_PREFIX}"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
  echo "Error: gcloud CLI is not installed"
  exit 1
fi

# Check if we're authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "Error: Not authenticated with gcloud. Please run 'gcloud auth login'"
  exit 1
fi

# Set the project
gcloud config set project "${GCP_PROJECT}"

# Safety check: Verify secret prefix to avoid conflicts
echo "Safety check: Verifying secret prefix..."
if [ -z "${SECRET_PREFIX}" ] || [ "${SECRET_PREFIX}" = "" ]; then
  echo "❌ ERROR: Secret prefix is empty!"
  exit 1
fi

# List existing secrets to show what we're NOT touching
echo ""
echo "Safety check: Existing secrets (non-n8n):"
EXISTING_SECRETS=$(gcloud secrets list --project="${GCP_PROJECT}" --format="value(name)" 2>/dev/null | grep -v "^${SECRET_PREFIX}" || echo "")
if [ -n "${EXISTING_SECRETS}" ]; then
  echo "${EXISTING_SECRETS}" | head -5 | while read -r secret; do
    echo "  - ${secret} (will NOT be modified)"
  done
  if [ $(echo "${EXISTING_SECRETS}" | wc -l) -gt 5 ]; then
    echo "  ... and $(($(echo "${EXISTING_SECRETS}" | wc -l) - 5)) more"
  fi
else
  echo "  (no existing secrets found)"
fi
echo ""
echo "⚠ IMPORTANT: This script will create secrets with prefix '${SECRET_PREFIX}'"
echo "   It will NOT modify any existing secrets without this prefix."
echo ""

# Enable Secret Manager API if not already enabled
echo "Checking Secret Manager API..."
if ! gcloud services list --enabled --project="${GCP_PROJECT}" --format="value(name)" | grep -q "secretmanager.googleapis.com"; then
  echo "Enabling Secret Manager API..."
  gcloud services enable secretmanager.googleapis.com --project="${GCP_PROJECT}"
fi
echo "✓ Secret Manager API enabled"

# Function to create or update a secret
create_or_update_secret() {
  local secret_name="$1"
  local secret_value="$2"
  local full_secret_name="${SECRET_PREFIX}${secret_name}"
  
  if [ -z "$secret_value" ]; then
    echo "⚠ Skipping ${full_secret_name} (empty value)"
    return 0
  fi
  
  # Check if secret exists
  if gcloud secrets describe "${full_secret_name}" --project="${GCP_PROJECT}" &>/dev/null; then
    echo "  Updating existing secret: ${full_secret_name}"
    echo -n "${secret_value}" | gcloud secrets versions add "${full_secret_name}" \
      --data-file=- \
      --project="${GCP_PROJECT}" >/dev/null
  else
    echo "  Creating new secret: ${full_secret_name}"
    echo -n "${secret_value}" | gcloud secrets create "${full_secret_name}" \
      --data-file=- \
      --replication-policy="automatic" \
      --project="${GCP_PROJECT}" >/dev/null
  fi
  
  # Grant access to service account
  gcloud secrets add-iam-policy-binding "${full_secret_name}" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="${GCP_PROJECT}" >/dev/null 2>&1 || true
}

# Prompt for required values
echo "Collecting required configuration values..."
echo ""

# Database password
if [ -z "${DB_PASSWORD}" ]; then
  read -sp "Enter database password for '${DB_USER}': " DB_PASSWORD
  echo ""
  if [ -z "${DB_PASSWORD}" ]; then
    echo "Error: Database password cannot be empty"
    exit 1
  fi
else
  echo "Using DB_PASSWORD from environment variable"
fi

# Redis password (from existing Redis)
if [ -z "${REDIS_PASSWORD}" ]; then
  echo "Redis password is required (from existing Memorystore instance)"
  read -sp "Enter Redis password: " REDIS_PASSWORD
  echo ""
else
  echo "Using REDIS_PASSWORD from environment variable"
fi

# GCS Access Key (from existing bucket)
if [ -z "${GCS_ACCESS_KEY}" ]; then
  echo "GCS Access Key is required (from existing bucket credentials)"
  read -sp "Enter GCS Access Key: " GCS_ACCESS_KEY
  echo ""
else
  echo "Using GCS_ACCESS_KEY from environment variable"
fi

# GCS Secret Key
if [ -z "${GCS_SECRET_KEY}" ]; then
  read -sp "Enter GCS Secret Key: " GCS_SECRET_KEY
  echo ""
else
  echo "Using GCS_SECRET_KEY from environment variable"
fi

# Encryption key (generate if not provided)
if [ -z "${N8N_ENCRYPTION_KEY}" ]; then
  if [ -z "${SKIP_CONFIRM}" ]; then
    echo ""
    read -p "Generate new encryption key? (yes/no, default: yes): " GENERATE_KEY
    GENERATE_KEY="${GENERATE_KEY:-yes}"
  else
    GENERATE_KEY="yes"
  fi
  if [ "${GENERATE_KEY}" = "yes" ]; then
    N8N_ENCRYPTION_KEY=$(generate_encryption_key)
    echo "✓ Generated new encryption key"
  else
    read -sp "Enter N8N_ENCRYPTION_KEY: " N8N_ENCRYPTION_KEY
    echo ""
  fi
else
  echo "Using N8N_ENCRYPTION_KEY from environment variable"
fi

# Values are now stored in environment variables and will be retrieved via get_env_var function

echo ""
echo "Creating secrets in Secret Manager..."
echo ""

# Create secrets for all environment variables
for var_name in $(get_all_env_var_names); do
  var_value=$(get_env_var "$var_name")
  create_or_update_secret "${var_name}" "${var_value}"
done

echo ""
echo "=========================================="
echo "Secrets setup completed successfully!"
echo "=========================================="
echo ""
echo "Created/updated secrets:"
gcloud secrets list --project="${GCP_PROJECT}" --filter="name~^${SECRET_PREFIX}" --format="table(name,createTime)" | head -20
echo ""
echo "To verify infrastructure, run:"
echo "  cd ${SCRIPT_DIR}"
echo "  ./verify-infrastructure.sh"
echo ""
