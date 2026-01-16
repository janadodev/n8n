#!/bin/bash
# Stage 2: Push Docker image and deploy to Cloud Run
# This script creates Docker image, pushes to GCR, and deploys

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${SCRIPT_DIR}/../config/project-config.sh"

echo "=========================================="
echo "Stage 2: Push and Deploy"
echo "=========================================="
echo "Project: ${GCP_PROJECT}"
echo "Repository: ${GCR_REPOSITORY}"
echo "Tag: ${IMAGE_TAG}"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
  echo "Error: gcloud CLI is not installed"
  exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Error: Docker is not installed"
  exit 1
fi

# Check if we're authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "Error: Not authenticated with gcloud. Please run 'gcloud auth login'"
  exit 1
fi

# Set the project
gcloud config set project "${GCP_PROJECT}"

# Configure Docker to use gcloud as a credential helper
echo "Configuring Docker authentication..."
gcloud auth configure-docker --quiet

# Check if compiled directory exists
echo ""
echo "Checking if application is built..."
if [ ! -d "${REPO_ROOT}/compiled" ]; then
  echo "❌ Error: Application not built. 'compiled' directory not found."
  echo ""
  echo "Run Stage 1 first:"
  echo "  cd ${SCRIPT_DIR}"
  echo "  ./build.sh"
  exit 1
fi
echo "✓ Application is built"

# Get git information for tagging
cd "${REPO_ROOT}"
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Determine N8N version from package.json or use git tag
N8N_VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "snapshot")

# Build Docker image
echo ""
echo "Step 1: Building Docker image..."

IMAGE_NAME="${GCR_REPOSITORY}:${IMAGE_TAG}"
IMAGE_NAME_COMMIT="${GCR_REPOSITORY}:${GIT_COMMIT}"
IMAGE_NAME_VERSION="${GCR_REPOSITORY}:${N8N_VERSION}"

echo "Building image: ${IMAGE_NAME}"
echo "  Git commit: ${GIT_COMMIT}"
echo "  Git branch: ${GIT_BRANCH}"
echo "  Build date: ${BUILD_DATE}"

cd "${REPO_ROOT}"
docker build \
  --file docker/images/n8n/Dockerfile \
  --tag "${IMAGE_NAME}" \
  --tag "${IMAGE_NAME_COMMIT}" \
  --tag "${IMAGE_NAME_VERSION}" \
  --build-arg N8N_VERSION="${N8N_VERSION}" \
  --build-arg N8N_RELEASE_TYPE=production \
  .

if [ $? -ne 0 ]; then
  echo "❌ Docker build failed"
  exit 1
fi

echo "✓ Docker image built successfully"

# Push to GCR
echo ""
echo "Step 2: Pushing image to Google Container Registry..."

echo "Pushing ${IMAGE_NAME}..."
docker push "${IMAGE_NAME}"

if [ "${IMAGE_TAG}" != "latest" ]; then
  echo "Pushing ${IMAGE_NAME_COMMIT}..."
  docker push "${IMAGE_NAME_COMMIT}"
  
  echo "Pushing ${IMAGE_NAME_VERSION}..."
  docker push "${IMAGE_NAME_VERSION}"
fi

echo "✓ Image pushed successfully"

# Verify the image
echo ""
echo "Step 3: Verifying image..."
if gcloud container images describe "${IMAGE_NAME}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "✓ Image verified in GCR"
  
  # Get image digest
  IMAGE_DIGEST=$(gcloud container images describe "${IMAGE_NAME}" --project="${GCP_PROJECT}" --format="value(image_summary.fully_qualified_digest)")
  echo "  Image digest: ${IMAGE_DIGEST}"
else
  echo "⚠ Warning: Could not verify image in GCR"
fi

# Deploy to Cloud Run
echo ""
echo "Step 4: Deploying to Cloud Run..."

# Verify secrets exist
source "${SCRIPT_DIR}/../config/env-vars.sh"

MISSING_SECRETS=()
for var_name in "${ALL_ENV_VAR_NAMES[@]}"; do
  secret_name="${SECRET_PREFIX}${var_name}"
  if ! gcloud secrets describe "${secret_name}" --project="${GCP_PROJECT}" &>/dev/null; then
    MISSING_SECRETS+=("${secret_name}")
  fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
  echo "❌ Error: Missing secrets:"
  for secret in "${MISSING_SECRETS[@]}"; do
    echo "   - ${secret}"
  done
  echo ""
  echo "Please set up secrets first:"
  echo "  cd ${SCRIPT_DIR}/../infrastructure"
  echo "  ./setup-secrets.sh"
  exit 1
fi
echo "✓ All secrets verified"

# Deploy the service
CLOUDRUN_YAML="${SCRIPT_DIR}/cloudrun.yaml"

if [ ! -f "${CLOUDRUN_YAML}" ]; then
  echo "❌ Error: cloudrun.yaml not found at ${CLOUDRUN_YAML}"
  exit 1
fi

# Update image in YAML if IMAGE_TAG is not latest
if [ "${IMAGE_TAG}" != "latest" ]; then
  echo "Updating image tag in cloudrun.yaml to ${IMAGE_TAG}..."
  sed -i.bak "s|image: ${GCR_REPOSITORY}:latest|image: ${GCR_REPOSITORY}:${IMAGE_TAG}|g" "${CLOUDRUN_YAML}"
  trap "mv ${CLOUDRUN_YAML}.bak ${CLOUDRUN_YAML}" EXIT
fi

# Deploy the service
gcloud run services replace "${CLOUDRUN_YAML}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT}"

if [ $? -ne 0 ]; then
  echo "❌ Deployment failed"
  exit 1
fi

# Restore YAML if modified
if [ -f "${CLOUDRUN_YAML}.bak" ]; then
  mv "${CLOUDRUN_YAML}.bak" "${CLOUDRUN_YAML}"
fi

echo "✓ Deployment successful"

# Get service URL
echo ""
echo "Getting service URL..."
SERVICE_URL=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT}" \
  --format="value(status.url)")

if [ -z "${SERVICE_URL}" ]; then
  echo "⚠ Warning: Could not retrieve service URL"
else
  echo "✓ Service URL: ${SERVICE_URL}"
fi

# Wait for service to be ready
echo ""
echo "Waiting for service to be ready..."
sleep 5

# Check service status
SERVICE_STATUS=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT}" \
  --format="value(status.conditions[0].status)")

if [ "${SERVICE_STATUS}" = "True" ]; then
  echo "✓ Service is ready"
else
  echo "⚠ Warning: Service status is ${SERVICE_STATUS}"
fi

# Summary
echo ""
echo "=========================================="
echo "Stage 2 completed successfully!"
echo "=========================================="
echo ""
echo "Service: ${CLOUD_RUN_SERVICE}"
echo "Region: ${GCP_REGION}"
echo "URL: ${SERVICE_URL}"
echo ""
echo "To view logs:"
echo "  gcloud run services logs read ${CLOUD_RUN_SERVICE} --region=${GCP_REGION} --project=${GCP_PROJECT}"
echo ""
