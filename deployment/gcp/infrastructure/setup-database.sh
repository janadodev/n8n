#!/bin/bash
# Setup n8n database in existing Cloud SQL instance
# This script creates the database and user for n8n

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/project-config.sh"

echo "=========================================="
echo "Setting up n8n database in Cloud SQL"
echo "=========================================="
echo "Project: ${GCP_PROJECT}"
echo "Instance: ${CLOUD_SQL_INSTANCE}"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
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

# Check if Cloud SQL instance exists
echo "Checking Cloud SQL instance..."
if ! gcloud sql instances describe "${CLOUD_SQL_INSTANCE##*:}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "Error: Cloud SQL instance '${CLOUD_SQL_INSTANCE##*:}' not found"
  exit 1
fi
echo "✓ Cloud SQL instance found"

# Safety check: Verify we're not accidentally using docmost database name
if [ "${DB_NAME}" = "docmost" ]; then
  echo "❌ ERROR: Database name 'docmost' is protected!"
  echo "   This script creates a NEW database for n8n, not the existing docmost database."
  echo "   Current database name: ${DB_NAME}"
  echo "   Please use a different database name in project-config.sh"
  exit 1
fi

# Safety check: Verify we're not accidentally using docmost user
if [ "${DB_USER}" = "postgres" ] || [ "${DB_USER}" = "docmost" ]; then
  echo "❌ ERROR: User name '${DB_USER}' is protected!"
  echo "   This script creates a NEW user for n8n, not an existing user."
  echo "   Current user name: ${DB_USER}"
  echo "   Please use a different user name in project-config.sh"
  exit 1
fi

# List existing databases to show what we're NOT touching
echo ""
echo "Safety check: Existing databases in this instance:"
EXISTING_DBS=$(gcloud sql databases list --instance="${CLOUD_SQL_INSTANCE##*:}" --project="${GCP_PROJECT}" --format="value(name)" 2>/dev/null || echo "")
if [ -n "${EXISTING_DBS}" ]; then
  echo "${EXISTING_DBS}" | while read -r db; do
    if [ "${db}" != "${DB_NAME}" ]; then
      echo "  - ${db} (will NOT be modified)"
    fi
  done
else
  echo "  (no existing databases found)"
fi
echo ""
echo "⚠ IMPORTANT: This script will create a NEW database '${DB_NAME}'"
echo "   It will NOT modify any existing databases."
echo ""
if [ -z "${SKIP_CONFIRM}" ]; then
  read -p "Continue? (yes/no): " CONFIRM
  if [ "${CONFIRM}" != "yes" ]; then
    echo "Aborted by user"
    exit 0
  fi
else
  echo "Skipping confirmation (SKIP_CONFIRM is set)"
fi

# Prompt for database password if not set
if [ -z "${DB_PASSWORD}" ]; then
  echo ""
  read -sp "Enter password for database user '${DB_USER}': " DB_PASSWORD
  echo ""
  if [ -z "${DB_PASSWORD}" ]; then
    echo "Error: Database password cannot be empty"
    exit 1
  fi
  read -sp "Confirm password: " DB_PASSWORD_CONFIRM
  echo ""
  if [ "${DB_PASSWORD}" != "${DB_PASSWORD_CONFIRM}" ]; then
    echo "Error: Passwords do not match"
    exit 1
  fi
else
  echo "Using DB_PASSWORD from environment variable"
fi

# Connect to Cloud SQL and create database
echo ""
echo "Connecting to Cloud SQL and creating database..."

# Create database using gcloud sql databases create
echo "Creating database '${DB_NAME}'..."
if gcloud sql databases describe "${DB_NAME}" --instance="${CLOUD_SQL_INSTANCE##*:}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "⚠ Database '${DB_NAME}' already exists"
  read -p "Do you want to recreate it? This will DELETE ALL DATA! (yes/no): " RECREATE_DB
  if [ "${RECREATE_DB}" = "yes" ]; then
    echo "Deleting existing database..."
    gcloud sql databases delete "${DB_NAME}" \
      --instance="${CLOUD_SQL_INSTANCE##*:}" \
      --project="${GCP_PROJECT}" \
      --quiet
    echo "Creating new database..."
    gcloud sql databases create "${DB_NAME}" \
      --instance="${CLOUD_SQL_INSTANCE##*:}" \
      --project="${GCP_PROJECT}"
  else
    echo "Keeping existing database"
  fi
else
  gcloud sql databases create "${DB_NAME}" \
    --instance="${CLOUD_SQL_INSTANCE##*:}" \
    --project="${GCP_PROJECT}"
fi
echo "✓ Database '${DB_NAME}' ready"

# Create user
echo ""
echo "Creating user '${DB_USER}'..."
# Check if user exists
if gcloud sql users list --instance="${CLOUD_SQL_INSTANCE##*:}" --project="${GCP_PROJECT}" --format="value(name)" | grep -q "^${DB_USER}$"; then
  echo "⚠ User '${DB_USER}' already exists"
  read -p "Do you want to update the password? (yes/no): " UPDATE_PASSWORD
  if [ "${UPDATE_PASSWORD}" = "yes" ]; then
    gcloud sql users set-password "${DB_USER}" \
      --instance="${CLOUD_SQL_INSTANCE##*:}" \
      --password="${DB_PASSWORD}" \
      --project="${GCP_PROJECT}"
    echo "✓ Password updated"
  fi
else
  gcloud sql users create "${DB_USER}" \
    --instance="${CLOUD_SQL_INSTANCE##*:}" \
    --password="${DB_PASSWORD}" \
    --project="${GCP_PROJECT}"
  echo "✓ User '${DB_USER}' created"
fi

# Grant privileges (PostgreSQL)
echo ""
echo "Granting privileges to user..."
# Connect and grant privileges
gcloud sql connect "${CLOUD_SQL_INSTANCE##*:}" \
  --user=postgres \
  --project="${GCP_PROJECT}" \
  --quiet <<EOF
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
GRANT ALL ON SCHEMA public TO ${DB_USER};
\q
EOF

echo "✓ Privileges granted"

# Save password to a temporary file for secret creation (will be cleaned up)
echo ""
echo "=========================================="
echo "Database setup completed successfully!"
echo "=========================================="
echo ""
echo "Database details:"
echo "  Instance: ${CLOUD_SQL_INSTANCE}"
echo "  Database: ${DB_NAME}"
echo "  User: ${DB_USER}"
echo ""
echo "⚠ IMPORTANT: Save the database password!"
echo "  You will need it when setting up secrets."
echo "  Password: ${DB_PASSWORD}"
echo ""
echo "To set up secrets, run:"
echo "  cd ${SCRIPT_DIR}"
echo "  ./setup-secrets.sh"
echo ""
