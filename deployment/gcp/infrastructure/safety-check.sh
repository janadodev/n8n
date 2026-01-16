#!/bin/bash
# Safety check script - Verify we won't damage existing docmost infrastructure
# Run this BEFORE running setup scripts to ensure safety

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/project-config.sh"

echo "=========================================="
echo "Safety Check: Protecting Existing Infrastructure"
echo "=========================================="
echo "Project: ${GCP_PROJECT}"
echo ""

ERRORS=0

# Check Cloud SQL instance
echo "1. Checking Cloud SQL instance..."
CLOUD_SQL_INSTANCE_NAME="${CLOUD_SQL_INSTANCE##*:}"
if gcloud sql instances describe "${CLOUD_SQL_INSTANCE_NAME}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "   ✓ Cloud SQL instance '${CLOUD_SQL_INSTANCE_NAME}' exists"
  
  # Check existing databases
  echo ""
  echo "   Existing databases:"
  EXISTING_DBS=$(gcloud sql databases list --instance="${CLOUD_SQL_INSTANCE_NAME}" --project="${GCP_PROJECT}" --format="value(name)" 2>/dev/null || echo "")
  if echo "${EXISTING_DBS}" | grep -q "docmost"; then
    echo "     ✓ Found 'docmost' database (will NOT be modified)"
  else
    echo "     ⚠ 'docmost' database not found (may not exist yet)"
  fi
  
  if echo "${EXISTING_DBS}" | grep -q "^${DB_NAME}$"; then
    echo "     ⚠ Database '${DB_NAME}' already exists (will be reused, not recreated unless confirmed)"
  else
    echo "     ✓ Database '${DB_NAME}' will be created (new, safe)"
  fi
  
  # Check existing users
  echo ""
  echo "   Existing users:"
  EXISTING_USERS=$(gcloud sql users list --instance="${CLOUD_SQL_INSTANCE_NAME}" --project="${GCP_PROJECT}" --format="value(name)" 2>/dev/null || echo "")
  if echo "${EXISTING_USERS}" | grep -q "postgres"; then
    echo "     ✓ Found 'postgres' user (will NOT be modified)"
  fi
  if echo "${EXISTING_USERS}" | grep -q "docmost"; then
    echo "     ✓ Found 'docmost' user (will NOT be modified)"
  fi
  if echo "${EXISTING_USERS}" | grep -q "^${DB_USER}$"; then
    echo "     ⚠ User '${DB_USER}' already exists (password will be updated if confirmed)"
  else
    echo "     ✓ User '${DB_USER}' will be created (new, safe)"
  fi
else
  echo "   ❌ Cloud SQL instance '${CLOUD_SQL_INSTANCE_NAME}' not found"
  ERRORS=$((ERRORS + 1))
fi

# Check Redis instance
echo ""
echo "2. Checking Redis instance..."
if gcloud redis instances describe "${REDIS_INSTANCE}" --region="${GCP_REGION}" --project="${GCP_PROJECT}" &>/dev/null; then
  REDIS_STATUS=$(gcloud redis instances describe "${REDIS_INSTANCE}" --region="${GCP_REGION}" --project="${GCP_PROJECT}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
  echo "   ✓ Redis instance '${REDIS_INSTANCE}' exists (status: ${REDIS_STATUS})"
  echo "   ✓ n8n will use DB index ${REDIS_DB_INDEX} (docmost uses DB 0, safe isolation)"
else
  echo "   ❌ Redis instance '${REDIS_INSTANCE}' not found"
  ERRORS=$((ERRORS + 1))
fi

# Check Storage bucket
echo ""
echo "3. Checking Cloud Storage bucket..."
if gcloud storage buckets describe "gs://${STORAGE_BUCKET}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "   ✓ Storage bucket '${STORAGE_BUCKET}' exists"
  echo "   ✓ n8n will use this bucket with its own folder structure (safe isolation)"
else
  echo "   ❌ Storage bucket '${STORAGE_BUCKET}' not found"
  ERRORS=$((ERRORS + 1))
fi

# Check existing secrets
echo ""
echo "4. Checking existing secrets..."
EXISTING_SECRETS=$(gcloud secrets list --project="${GCP_PROJECT}" --format="value(name)" 2>/dev/null || echo "")
N8N_SECRETS=$(echo "${EXISTING_SECRETS}" | grep "^${SECRET_PREFIX}" || echo "")
OTHER_SECRETS=$(echo "${EXISTING_SECRETS}" | grep -v "^${SECRET_PREFIX}" || echo "")

if [ -n "${OTHER_SECRETS}" ]; then
  OTHER_COUNT=$(echo "${OTHER_SECRETS}" | wc -l | tr -d ' ')
  echo "   ✓ Found ${OTHER_COUNT} existing secrets (will NOT be modified)"
  echo "     Examples:"
  echo "${OTHER_SECRETS}" | head -3 | while read -r secret; do
    echo "       - ${secret}"
  done
  if [ ${OTHER_COUNT} -gt 3 ]; then
    echo "       ... and $((OTHER_COUNT - 3)) more"
  fi
fi

if [ -n "${N8N_SECRETS}" ]; then
  N8N_COUNT=$(echo "${N8N_SECRETS}" | wc -l | tr -d ' ')
  echo "   ⚠ Found ${N8N_COUNT} existing n8n secrets (will be updated if re-run)"
else
  echo "   ✓ No existing n8n secrets (will create new ones)"
fi

# Check Cloud Run services
echo ""
echo "5. Checking existing Cloud Run services..."
EXISTING_SERVICES=$(gcloud run services list --region="${GCP_REGION}" --project="${GCP_PROJECT}" --format="value(metadata.name)" 2>/dev/null || echo "")
if echo "${EXISTING_SERVICES}" | grep -q "docmost"; then
  echo "   ✓ Found 'docmost' service (will NOT be modified)"
fi
if echo "${EXISTING_SERVICES}" | grep -q "^${CLOUD_RUN_SERVICE}$"; then
  echo "   ⚠ Service '${CLOUD_RUN_SERVICE}' already exists (will be updated during deployment)"
else
  echo "   ✓ Service '${CLOUD_RUN_SERVICE}' will be created (new, safe)"
fi

# Summary
echo ""
echo "=========================================="
echo "Safety Check Summary"
echo "=========================================="
echo ""

if [ ${ERRORS} -eq 0 ]; then
  echo "✓ All safety checks passed!"
  echo ""
  echo "This setup will:"
  echo "  ✓ Create NEW database '${DB_NAME}' (isolated from docmost)"
  echo "  ✓ Create NEW user '${DB_USER}' (isolated from docmost)"
  echo "  ✓ Use Redis DB index ${REDIS_DB_INDEX} (docmost uses DB 0)"
  echo "  ✓ Use existing bucket with separate folder structure"
  echo "  ✓ Create secrets with prefix '${SECRET_PREFIX}' (isolated from other secrets)"
  echo "  ✓ Create NEW Cloud Run service '${CLOUD_RUN_SERVICE}'"
  echo ""
  echo "This setup will NOT:"
  echo "  ✗ Modify existing 'docmost' database"
  echo "  ✗ Modify existing 'docmost' users"
  echo "  ✗ Modify existing secrets without '${SECRET_PREFIX}' prefix"
  echo "  ✗ Modify existing 'docmost' Cloud Run service"
  echo "  ✗ Modify Redis instance configuration"
  echo "  ✗ Modify Cloud Storage bucket configuration"
  echo ""
  echo "You can safely proceed with infrastructure setup."
  exit 0
else
  echo "❌ Some safety checks failed!"
  echo ""
  echo "Please fix the errors above before proceeding."
  exit 1
fi
