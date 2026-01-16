# n8n GCP Deployment Guide

This directory contains scripts and configuration for deploying n8n to Google Cloud Platform using existing infrastructure in the `docmost-484110` project.

## Architecture Overview

n8n is deployed as a Cloud Run service that uses:

- **Cloud SQL (PostgreSQL)**: Existing instance `docmost-2` with a new database `n8n`
- **Memorystore (Redis)**: Existing instance `docmost` using DB index 1 (docmost uses DB 0)
- **Cloud Storage**: Existing bucket `ja-docmost` for binary data storage
- **Secret Manager**: All environment variables stored as secrets with prefix `n8n-`

## Directory Structure

```
deployment/gcp/
├── config/                    # Configuration files
│   ├── project-config.sh     # GCP project settings
│   └── env-vars.sh           # Environment variable definitions
├── infrastructure/            # Infrastructure setup (run once)
│   ├── setup-database.sh     # Create database and user
│   ├── setup-secrets.sh      # Create secrets in Secret Manager
│   ├── verify-infrastructure.sh  # Verify all components
│   └── README.md             # Infrastructure documentation
├── deploy/                    # Application deployment
│   ├── build-and-push.sh     # Build and push Docker image
│   ├── deploy-cloudrun.sh    # Deploy to Cloud Run
│   ├── cloudrun.yaml         # Cloud Run service configuration
│   └── README.md             # Deployment documentation
└── README.md                  # This file
```

## Prerequisites

1. **GCP Access**: Access to project `docmost-484110` with appropriate permissions
2. **gcloud CLI**: Installed and authenticated (`gcloud auth login`)
3. **Docker**: Installed and running
4. **Node.js & pnpm**: For building the application (Node.js 22.16+, pnpm 10.22+)
5. **Existing Resources**: 
   - Cloud SQL instance: `docmost-2`
   - Memorystore Redis: `docmost`
   - Cloud Storage bucket: `ja-docmost`

## Quick Start

### 1. Initial Infrastructure Setup (One-time)

```bash
cd deployment/gcp/infrastructure

# Step 0: Safety check (RECOMMENDED - verifies we won't damage existing infrastructure)
./safety-check.sh

# Step 1: Create database
./setup-database.sh

# Step 2: Create secrets
./setup-secrets.sh

# Step 3: Verify everything is ready
./verify-infrastructure.sh
```

### 2. Deploy Application (Two Independent Stages)

**Stage 1: Build Application (Independent)**
```bash
cd deployment/gcp/deploy

# Build your code (creates compiled/ directory)
./build.sh
```

**Stage 2: Push and Deploy (Independent)**
```bash
# After Stage 1 completes, push image and deploy
./push-and-deploy.sh
```

**Note:** These two stages are completely independent. You can:
- Run Stage 1 multiple times to build different versions
- Run Stage 2 separately after any successful build
- Stage 2 creates Docker image, pushes to GCR, and deploys in one step

## Detailed Instructions

### Infrastructure Setup

See [infrastructure/README.md](infrastructure/README.md) for detailed instructions on setting up:
- Database creation
- Secret Manager configuration
- Infrastructure verification

### Application Deployment

See [deploy/README.md](deploy/README.md) for detailed instructions on:
- Building Docker images
- Deploying to Cloud Run
- Updating the service

## Configuration

### Project Configuration

Edit `config/project-config.sh` to modify:
- GCP project, region, zone
- Resource names (Cloud SQL, Redis, Storage)
- Cloud Run settings (CPU, memory, scaling)

### Environment Variables

Edit `config/env-vars.sh` to modify:
- Application settings
- Database configuration
- Redis configuration
- Storage configuration

All environment variables are stored in Secret Manager with the prefix `n8n-`.

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   ```bash
   gcloud auth login
   gcloud config set project docmost-484110
   ```

2. **Missing Secrets**
   ```bash
   cd deployment/gcp/infrastructure
   ./setup-secrets.sh
   ```

3. **Database Connection Issues**
   - Verify Cloud SQL instance is running
   - Check service account has `roles/cloudsql.client` permission
   - Verify Cloud SQL connection name in `cloudrun.yaml`

4. **Image Build Failures**
   - Ensure `pnpm build:deploy` completes successfully
   - Check Docker has enough resources allocated
   - Verify you're in the repository root

5. **Deployment Failures**
   - Check all secrets exist: `gcloud secrets list --filter="name~^n8n-"`
   - Verify image exists: `gcloud container images list --repository=gcr.io/docmost-484110`
   - Check Cloud Run logs: `gcloud run services logs read n8n --region=europe-west1`

### Getting Help

- Check service logs: `gcloud run services logs read n8n --region=europe-west1 --project=docmost-484110`
- View service details: `gcloud run services describe n8n --region=europe-west1 --project=docmost-484110`
- Check infrastructure: `cd deployment/gcp/infrastructure && ./verify-infrastructure.sh`

## Security Notes

- All sensitive data is stored in Secret Manager
- Service account has minimal required permissions
- Database uses separate user with limited privileges
- Redis uses separate DB index for isolation
- Cloud Storage bucket has appropriate access controls

## Updating the Deployment

To update n8n after code changes:

```bash
cd deployment/gcp/deploy
./build-and-push.sh
./deploy-cloudrun.sh
```

The deployment script will:
1. Build the new application
2. Create a new Docker image
3. Push to Google Container Registry
4. Update the Cloud Run service with zero downtime

## Rollback

To rollback to a previous version:

```bash
# List available image tags
gcloud container images list-tags gcr.io/docmost-484110/n8n

# Update IMAGE_TAG and redeploy
export IMAGE_TAG=<previous-tag>
cd deployment/gcp/deploy
./deploy-cloudrun.sh
```

Or update the image directly:

```bash
gcloud run services update n8n \
  --image=gcr.io/docmost-484110/n8n:<previous-tag> \
  --region=europe-west1 \
  --project=docmost-484110
```
