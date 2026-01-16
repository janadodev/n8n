# Application Deployment

This directory contains scripts for building and deploying the n8n application to Google Cloud Run.

## Two-Stage Deployment Process

The deployment is split into **two independent stages** that can be run separately:

### Stage 1: Build Application (Independent)

**Script:** `build.sh`

**What it does:**
1. Builds the n8n application using `pnpm build:deploy`
2. Creates `compiled/` directory with built application

**Does NOT:**
- Create Docker image
- Push to GCR
- Deploy anything

**Requirements:**
- Node.js 22.16+ (recommended) or 20.19+ (may work with warnings)
- pnpm 10.22+
- Docker installed and running
- gcloud CLI authenticated
- Repository dependencies installed (`pnpm install`)

**Usage:**
```bash
cd deployment/gcp/deploy
./build-and-push.sh
```

**Environment Variables:**
- `IMAGE_TAG` - Tag for the Docker image (default: `latest`)

**Example:**
```bash
# Build with specific tag
IMAGE_TAG=v1.0.0 ./build-and-push.sh

# Build with git commit as tag
IMAGE_TAG=$(git rev-parse --short HEAD) ./build-and-push.sh
```

**Output:**
- Creates `compiled/` directory with built application

**This stage is completely independent** - it only builds the application. It does not create Docker image or deploy anything.

---

### Stage 2: Push and Deploy (Independent)

**Script:** `push-and-deploy.sh`

**What it does:**
1. Verifies `compiled/` directory exists (from Stage 1)
2. Creates Docker image from compiled application
3. Tags the image with multiple tags (latest, git commit, version)
4. Pushes the image to Google Container Registry
5. Verifies all required secrets exist
6. Deploys the service using `cloudrun.yaml`
7. Waits for deployment to complete
8. Displays the service URL

**Requirements:**
- Application built (Stage 1 completed) - `compiled/` directory must exist
- Docker installed and running
- gcloud CLI authenticated
- All secrets created in Secret Manager
- Infrastructure setup completed

**Usage:**
```bash
cd deployment/gcp/deploy
./deploy-cloudrun.sh
```

**Environment Variables:**
- `IMAGE_TAG` - Tag of the image to deploy (default: `latest`)
- `USE_OFFICIAL_IMAGE` - Set to `true` to use official n8n image instead of custom build

**Examples:**
```bash
# Push and deploy latest image
./push-and-deploy.sh

# Push and deploy with specific tag
IMAGE_TAG=v1.0.0 ./push-and-deploy.sh
```

**This stage is completely independent** - it creates Docker image, pushes it, and deploys. It requires Stage 1 to be completed first.

---

## Complete Deployment Workflow

### Option 1: Two Separate Steps (Recommended)

```bash
# Step 1: Build application (can take 5-10 minutes)
cd deployment/gcp/deploy
./build.sh

# Step 2: Push and deploy (after Step 1 completes)
./push-and-deploy.sh
```

### Option 2: Combined Script

```bash
# Builds and deploys in one command
cd deployment/gcp/deploy
./deploy.sh
```

---

## Scripts Overview

### `build.sh`

Builds the n8n application only.

**Independent:** ✅ Yes - can be run standalone
**Dependencies:** Node.js, pnpm
**Output:** `compiled/` directory with built application

### `push-and-deploy.sh`

Creates Docker image, pushes to GCR, and deploys to Cloud Run.

**Independent:** ✅ Yes - can be run standalone (requires Stage 1 completed)
**Dependencies:** `compiled/` directory (from Stage 1), Docker, gcloud, secrets in Secret Manager
**Output:** Deployed Cloud Run service

### `build-and-push.sh` (Legacy)

Legacy script that combines build and push. Use `build.sh` + `push-and-deploy.sh` instead.

### `deploy-cloudrun.sh` (Legacy)

Legacy script for deploying existing images. Use `push-and-deploy.sh` instead.

### `deploy.sh`

Convenience script that runs both stages sequentially.

**Independent:** ⚠️ No - combines both stages
**Use when:** You want to build and deploy in one command

### `cloudrun.yaml`

Cloud Run service configuration file. This file defines:
- Service name and metadata
- Container image and resources
- Environment variables (from Secret Manager)
- Health checks (startup, liveness, readiness)
- Scaling configuration
- Cloud SQL connection

**Note:** This file is used as-is. The `deploy-cloudrun.sh` script may temporarily modify the image tag if `IMAGE_TAG` is not `latest`.

---

## Deployment Process

### Initial Deployment

1. **Build the application:**
   ```bash
   ./build.sh
   ```

2. **Push and deploy:**
   ```bash
   ./push-and-deploy.sh
   ```

### Updating the Deployment

To update n8n after code changes:

```bash
# Build new version
./build.sh

# Push and deploy new version
./push-and-deploy.sh
```

The deployment uses rolling updates, so there should be no downtime.

### Deploying a Specific Version

```bash
# Build application
./build.sh

# Push and deploy with specific tag
IMAGE_TAG=v1.2.3 ./push-and-deploy.sh
```

---

## Configuration

### Cloud Run Settings

Edit `cloudrun.yaml` to modify:
- CPU and memory limits
- Min/max instances
- Timeout settings
- Health check configuration
- Environment variables

### Image Configuration

The Docker image is built using:
- Base image: `n8nio/base:22.21.1`
- Build context: Repository root
- Dockerfile: `docker/images/n8n/Dockerfile`
- Compiled code: `./compiled` directory

---

## Monitoring

### View Logs

```bash
gcloud run services logs read n8n \
  --region=europe-west1 \
  --project=docmost-484110 \
  --limit=50
```

### View Service Status

```bash
gcloud run services describe n8n \
  --region=europe-west1 \
  --project=docmost-484110
```

### Check Service Health

```bash
# Get service URL
SERVICE_URL=$(gcloud run services describe n8n \
  --region=europe-west1 \
  --project=docmost-484110 \
  --format="value(status.url)")

# Check health endpoint
curl "${SERVICE_URL}/healthz"
```

---

## Troubleshooting

### Build Failures

**Error: pnpm build:deploy fails**
- Ensure all dependencies are installed: `pnpm install`
- Check Node.js version: `node --version` (should be 22.16+)
- Check pnpm version: `pnpm --version` (should be 10.22+)
- Review build logs for specific errors

**Error: Docker build fails**
- Ensure Docker is running: `docker ps`
- Check available disk space: `df -h`
- Verify `compiled/` directory exists after build
- Check Docker logs: `docker build --progress=plain ...`

**Error: Image push fails**
- Verify authentication: `gcloud auth configure-docker`
- Check GCR permissions
- Verify project is correct: `gcloud config get-value project`

### Deployment Failures

**Error: compiled directory not found**
- Run Stage 1 first: `./build.sh`
- Verify `compiled/` directory exists: `ls -la compiled/`

**Error: Secrets not found**
- Verify secrets exist: `gcloud secrets list --filter="name~^n8n-"`
- Re-run infrastructure setup if needed: `cd ../infrastructure && ./setup-secrets.sh`

**Error: Service deployment fails**
- Check Cloud Run quotas: `gcloud compute project-info describe --project=docmost-484110`
- Review deployment logs in Cloud Console
- Verify service account permissions

### Runtime Issues

**Service not starting**
- Check logs: `gcloud run services logs read n8n --region=europe-west1`
- Verify health checks: Check `/healthz` and `/healthz/readiness` endpoints
- Check database connectivity
- Verify Redis connectivity

**Database connection errors**
- Verify Cloud SQL instance is running
- Check service account has `roles/cloudsql.client`
- Verify connection name in `cloudrun.yaml` matches actual instance
- Check database credentials in Secret Manager

**Redis connection errors**
- Verify Redis instance is READY
- Check Redis host and port are correct
- Verify Redis password in Secret Manager
- Test connection from Cloud Run service

---

## Rollback

### Rollback to Previous Version

1. **List available image tags:**
   ```bash
   gcloud container images list-tags gcr.io/docmost-484110/n8n \
     --limit=10 \
     --sort-by=TIMESTAMP
   ```

2. **Update service to previous image:**
   ```bash
   gcloud run services update n8n \
     --image=gcr.io/docmost-484110/n8n:<previous-tag> \
     --region=europe-west1 \
     --project=docmost-484110
   ```

Or use the deploy script:
```bash
IMAGE_TAG=<previous-tag> ./deploy-cloudrun.sh
```

### Rollback Configuration Changes

If you need to rollback `cloudrun.yaml` changes:

1. Restore previous version from git
2. Redeploy: `./deploy-cloudrun.sh`

---

## Best Practices

1. **Tag images meaningfully** - Use version numbers or git commits
2. **Test before production** - Deploy to a test service first
3. **Monitor deployments** - Watch logs during and after deployment
4. **Keep backups** - Tag important versions for easy rollback
5. **Document changes** - Note what changed in each deployment

---

## Next Steps

After successful deployment:

1. Access the service URL provided by the deployment script
2. Complete initial n8n setup (create admin user)
3. Configure workflows and integrations
4. Set up monitoring and alerts
