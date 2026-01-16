#!/bin/bash
# Verify that all infrastructure components are ready
# This script checks Cloud SQL, Redis, Storage, and Secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/project-config.sh"
source "${SCRIPT_DIR}/../config/env-vars.sh"

echo "=========================================="
echo "Verifying n8n infrastructure"
echo "=========================================="
echo "Project: ${GCP_PROJECT}"
echo ""
echo "⚠ Safety check: This verification will NOT modify any existing resources."
echo "   It only reads information to verify infrastructure readiness."
echo ""

ERRORS=0
WARNINGS=0

# Check gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "❌ Error: Not authenticated with gcloud"
  ERRORS=$((ERRORS + 1))
  exit 1
fi

gcloud config set project "${GCP_PROJECT}" >/dev/null 2>&1

# Check Cloud SQL instance
echo "Checking Cloud SQL instance..."
CLOUD_SQL_INSTANCE_NAME="${CLOUD_SQL_INSTANCE##*:}"
if gcloud sql instances describe "${CLOUD_SQL_INSTANCE_NAME}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "✓ Cloud SQL instance '${CLOUD_SQL_INSTANCE_NAME}' exists"
  
  # Check database
  if gcloud sql databases describe "${DB_NAME}" --instance="${CLOUD_SQL_INSTANCE_NAME}" --project="${GCP_PROJECT}" &>/dev/null; then
    echo "  ✓ Database '${DB_NAME}' exists"
  else
    echo "  ❌ Database '${DB_NAME}' not found"
    ERRORS=$((ERRORS + 1))
  fi
  
  # Check user
  if gcloud sql users list --instance="${CLOUD_SQL_INSTANCE_NAME}" --project="${GCP_PROJECT}" --format="value(name)" | grep -q "^${DB_USER}$"; then
    echo "  ✓ User '${DB_USER}' exists"
  else
    echo "  ❌ User '${DB_USER}' not found"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "❌ Cloud SQL instance '${CLOUD_SQL_INSTANCE_NAME}' not found"
  ERRORS=$((ERRORS + 1))
fi

# Check Redis instance
echo ""
echo "Checking Redis instance..."
if gcloud redis instances describe "${REDIS_INSTANCE}" --region="${GCP_REGION}" --project="${GCP_PROJECT}" &>/dev/null; then
  REDIS_STATUS=$(gcloud redis instances describe "${REDIS_INSTANCE}" --region="${GCP_REGION}" --project="${GCP_PROJECT}" --format="value(state)")
  if [ "${REDIS_STATUS}" = "READY" ]; then
    echo "✓ Redis instance '${REDIS_INSTANCE}' exists and is READY"
    echo "  Host: ${REDIS_HOST}"
    echo "  Port: ${REDIS_PORT}"
    echo "  DB Index for n8n: ${REDIS_DB_INDEX}"
  else
    echo "⚠ Redis instance '${REDIS_INSTANCE}' exists but status is: ${REDIS_STATUS}"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  echo "❌ Redis instance '${REDIS_INSTANCE}' not found"
  ERRORS=$((ERRORS + 1))
fi

# Check Cloud Storage bucket
echo ""
echo "Checking Cloud Storage bucket..."
if gcloud storage buckets describe "gs://${STORAGE_BUCKET}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "✓ Storage bucket '${STORAGE_BUCKET}' exists"
else
  echo "❌ Storage bucket '${STORAGE_BUCKET}' not found"
  ERRORS=$((ERRORS + 1))
fi

# Check Secret Manager secrets
echo ""
echo "Checking Secret Manager secrets..."
SECRET_COUNT=0
MISSING_SECRETS=()

for var_name in $(get_all_env_var_names); do
  secret_name="${SECRET_PREFIX}${var_name}"
  if gcloud secrets describe "${secret_name}" --project="${GCP_PROJECT}" &>/dev/null; then
    SECRET_COUNT=$((SECRET_COUNT + 1))
  else
    MISSING_SECRETS+=("${secret_name}")
  fi
done

echo "  Found ${SECRET_COUNT} secrets"

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
  echo "  ❌ Missing secrets:"
  for secret in "${MISSING_SECRETS[@]}"; do
    echo "     - ${secret}"
  done
  ERRORS=$((ERRORS + ${#MISSING_SECRETS[@]}))
else
  echo "  ✓ All required secrets exist"
fi

# Check service account permissions
echo ""
echo "Checking service account permissions..."
if gcloud projects get-iam-policy "${GCP_PROJECT}" --flatten="bindings[].members" --filter="bindings.members:${SERVICE_ACCOUNT}" --format="value(bindings.role)" | grep -q "roles/secretmanager.secretAccessor"; then
  echo "✓ Service account has Secret Manager access"
else
  echo "⚠ Service account may not have Secret Manager access"
  WARNINGS=$((WARNINGS + 1))
fi

if gcloud projects get-iam-policy "${GCP_PROJECT}" --flatten="bindings[].members" --filter="bindings.members:${SERVICE_ACCOUNT}" --format="value(bindings.role)" | grep -q "roles/cloudsql.client"; then
  echo "✓ Service account has Cloud SQL access"
else
  echo "⚠ Service account may not have Cloud SQL access"
  WARNINGS=$((WARNINGS + 1))
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "Errors: ${ERRORS}"
echo "Warnings: ${WARNINGS}"
echo ""

if [ ${ERRORS} -eq 0 ]; then
  echo "✓ All infrastructure components are ready!"
  echo ""
  echo "You can now proceed with deployment:"
  echo "  cd ${SCRIPT_DIR}/../deploy"
  echo "  ./build-and-push.sh"
  echo "  ./deploy-cloudrun.sh"
  exit 0
else
  echo "❌ Some infrastructure components are missing or misconfigured"
  echo ""
  echo "Please fix the errors above before proceeding with deployment."
  exit 1
fi
