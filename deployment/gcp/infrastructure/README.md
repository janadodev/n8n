# Infrastructure Setup

This directory contains scripts for setting up the infrastructure required for n8n deployment. These scripts should be run **once** before the first deployment.

## Scripts Overview

### `setup-database.sh`

Creates the database and user for n8n in the existing Cloud SQL instance.

**What it does:**
- Connects to Cloud SQL instance `docmost-2`
- Creates database `n8n`
- Creates user `n8n_user` with secure password
- Grants necessary privileges

**Requirements:**
- Access to Cloud SQL instance
- gcloud CLI authenticated
- PostgreSQL client tools (via gcloud)

**Usage:**
```bash
./setup-database.sh
```

The script will prompt for:
- Database password (twice for confirmation)

**Note:** The password will be needed when running `setup-secrets.sh`.

### `setup-secrets.sh`

Creates all required secrets in Google Cloud Secret Manager.

**What it does:**
- Creates secrets for all n8n environment variables
- Stores secrets with prefix `n8n-`
- Grants service account access to secrets
- Auto-generates encryption key if not provided

**Requirements:**
- Secret Manager API enabled
- Service account exists
- Database password (from `setup-database.sh`)
- Redis password (from existing Memorystore)
- GCS access credentials (from existing bucket)

**Usage:**
```bash
./setup-secrets.sh
```

The script will prompt for:
- Database password
- Redis password
- GCS Access Key
- GCS Secret Key
- Encryption key (or generate new)

**Secrets Created:**
- `n8n-N8N_PROTOCOL`
- `n8n-N8N_PORT`
- `n8n-NODE_ENV`
- `n8n-DB_TYPE`
- `n8n-DB_POSTGRESDB_HOST`
- `n8n-DB_POSTGRESDB_DATABASE`
- `n8n-DB_POSTGRESDB_USER`
- `n8n-DB_POSTGRESDB_PASSWORD`
- `n8n-QUEUE_BULL_REDIS_HOST`
- `n8n-QUEUE_BULL_REDIS_PORT`
- `n8n-QUEUE_BULL_REDIS_DB`
- `n8n-QUEUE_BULL_REDIS_PASSWORD`
- `n8n-EXECUTIONS_MODE`
- `n8n-N8N_DEFAULT_BINARY_DATA_MODE`
- `n8n-N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME`
- `n8n-N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION`
- `n8n-N8N_EXTERNAL_STORAGE_S3_HOST`
- `n8n-N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY`
- `n8n-N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET`
- `n8n-N8N_ENCRYPTION_KEY`
- And more...

### `verify-infrastructure.sh`

Verifies that all infrastructure components are ready for deployment.

**What it checks:**
- Cloud SQL instance exists and is accessible
- Database `n8n` exists
- User `n8n_user` exists
- Redis instance exists and is READY
- Storage bucket exists
- All required secrets exist
- Service account has necessary permissions

**Usage:**
```bash
./verify-infrastructure.sh
```

**Output:**
- ✓ for successful checks
- ❌ for errors (must be fixed)
- ⚠ for warnings (should be reviewed)

## Setup Order

**IMPORTANT: Run the safety check first!**

Run the scripts in this order:

0. **`safety-check.sh`** - Verify we won't damage existing infrastructure (RECOMMENDED)
1. **`setup-database.sh`** - Create database and user
2. **`setup-secrets.sh`** - Create all secrets
3. **`verify-infrastructure.sh`** - Verify everything is ready

### Safety Check

Before running any setup scripts, run the safety check to ensure we won't accidentally modify existing docmost infrastructure:

```bash
./safety-check.sh
```

This script will:
- Verify existing resources (databases, users, secrets, services)
- Confirm that n8n setup will create NEW resources, not modify existing ones
- Show what will and won't be modified
- Provide a safety summary before proceeding

## Updating Secrets

To update a secret value:

```bash
# Update a specific secret
echo -n "new-value" | gcloud secrets versions add n8n-SECRET_NAME \
  --data-file=- \
  --project=docmost-484110

# The Cloud Run service will use the latest version automatically
```

To update multiple secrets, you can re-run `setup-secrets.sh` - it will update existing secrets instead of creating new ones.

## Troubleshooting

### Database Setup Issues

**Error: Cloud SQL instance not found**
- Verify the instance name in `../config/project-config.sh`
- Check you have access to the project: `gcloud projects list`

**Error: Permission denied**
- Ensure you have `roles/cloudsql.admin` or `roles/cloudsql.client`
- Check: `gcloud projects get-iam-policy docmost-484110 --flatten="bindings[].members" --filter="bindings.members:user:$(gcloud config get-value account)"`

### Secret Manager Issues

**Error: Secret Manager API not enabled**
- The script will attempt to enable it automatically
- If it fails, enable manually: `gcloud services enable secretmanager.googleapis.com`

**Error: Service account access denied**
- Verify service account exists: `gcloud iam service-accounts describe 584964349468-compute@developer.gserviceaccount.com`
- Grant access manually if needed

### Verification Issues

**Missing secrets**
- Re-run `setup-secrets.sh` to create missing secrets
- Check secret names match exactly (case-sensitive)

**Service account permissions**
- Ensure service account has:
  - `roles/secretmanager.secretAccessor`
  - `roles/cloudsql.client`
  - `roles/storage.objectViewer` (for Cloud Storage)

## Security Best Practices

1. **Never commit secrets** - All secrets are stored in Secret Manager
2. **Use strong passwords** - Database and Redis passwords should be complex
3. **Rotate secrets regularly** - Update secrets periodically
4. **Limit access** - Only grant necessary permissions to service accounts
5. **Audit access** - Review Secret Manager access logs regularly

## Next Steps

After infrastructure setup is complete:

1. Verify everything: `./verify-infrastructure.sh`
2. Proceed to deployment: `cd ../deploy && ./build-and-push.sh`
