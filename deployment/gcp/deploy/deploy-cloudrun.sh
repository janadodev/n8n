#!/bin/bash
# Deploy n8n to Google Cloud Run
# This script deploys the application using the cloudrun.yaml configuration

set -e

# Save the deploy script directory before sourcing config
DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${DEPLOY_SCRIPT_DIR}"

# Source config (this may change directory, so we restore it)
source "${SCRIPT_DIR}/../config/project-config.sh"

# Ensure we're in the deploy directory
cd "${DEPLOY_SCRIPT_DIR}"

echo "=========================================="
echo "Deploying n8n to Cloud Run"
echo "=========================================="
echo "Project: ${GCP_PROJECT}"
echo "Region: ${GCP_REGION}"
echo "Service: ${CLOUD_RUN_SERVICE}"
echo "Image: ${GCR_REPOSITORY}:${IMAGE_TAG}"
echo ""
echo "This script can be run independently after build-and-push.sh completes."
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

# Check if using official image or custom built image
if [ "${USE_OFFICIAL_IMAGE:-false}" = "true" ] || [ "${GCR_REPOSITORY}" = "docker.n8n.io/n8nio/n8n" ]; then
  echo "Using official n8n image: docker.n8n.io/n8nio/n8n:latest"
  USE_OFFICIAL_IMAGE=true
else
  # Verify custom image exists
  echo "Verifying Docker image exists in GCR..."
  if ! gcloud container images describe "${GCR_REPOSITORY}:${IMAGE_TAG}" --project="${GCP_PROJECT}" &>/dev/null; then
    echo "❌ Error: Docker image '${GCR_REPOSITORY}:${IMAGE_TAG}' not found in GCR"
    echo ""
    echo "The image must be built and pushed first. Run:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  ./build-and-push.sh"
    echo ""
    echo "Or use official image instead:"
    echo "  USE_OFFICIAL_IMAGE=true ./deploy-cloudrun.sh"
    echo ""
    echo "Available image tags in GCR:"
    gcloud container images list-tags "${GCR_REPOSITORY}" --project="${GCP_PROJECT}" --limit=5 2>/dev/null || echo "  (no images found)"
    exit 1
  fi
  echo "✓ Image verified: ${GCR_REPOSITORY}:${IMAGE_TAG}"
fi

# Verify secrets exist
echo ""
echo "Verifying secrets exist..."
source "${SCRIPT_DIR}/../config/env-vars.sh"

MISSING_SECRETS=()
for var_name in $(get_all_env_var_names); do
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

# Deploy to Cloud Run
echo ""
echo "Deploying to Cloud Run..."

# Use gcloud run services replace to deploy from YAML
# cloudrun.yaml should be in the same directory as this script
CLOUDRUN_YAML="${DEPLOY_SCRIPT_DIR}/cloudrun.yaml"

if [ ! -f "${CLOUDRUN_YAML}" ]; then
  echo "❌ Error: cloudrun.yaml not found at ${CLOUDRUN_YAML}"
  echo "Current directory: $(pwd)"
  echo "Script directory: ${SCRIPT_DIR}"
  echo "Files in script directory:"
  ls -la "${SCRIPT_DIR}" | head -10
  exit 1
fi

# Update image in YAML if IMAGE_TAG is not latest
if [ "${IMAGE_TAG}" != "latest" ]; then
  echo "Updating image tag in cloudrun.yaml to ${IMAGE_TAG}..."
  sed -i.bak "s|image: ${GCR_REPOSITORY}:latest|image: ${GCR_REPOSITORY}:${IMAGE_TAG}|g" "${CLOUDRUN_YAML}"
  trap "mv ${CLOUDRUN_YAML}.bak ${CLOUDRUN_YAML}" EXIT
fi

# Update image in YAML if using official image
if [ "${USE_OFFICIAL_IMAGE}" = "true" ]; then
  echo "Updating cloudrun.yaml to use official image..."
  sed -i.bak "s|image: .*|image: docker.n8n.io/n8nio/n8n:latest|g" "${CLOUDRUN_YAML}"
  trap "mv ${CLOUDRUN_YAML}.bak ${CLOUDRUN_YAML} 2>/dev/null || true" EXIT
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
echo "Deployment completed successfully!"
echo "=========================================="
echo ""
echo "Service: ${CLOUD_RUN_SERVICE}"
echo "Region: ${GCP_REGION}"
echo "URL: ${SERVICE_URL}"
echo ""
echo "To view logs:"
echo "  gcloud run services logs read ${CLOUD_RUN_SERVICE} --region=${GCP_REGION} --project=${GCP_PROJECT}"
echo ""
echo "To update the service:"
echo "  cd ${SCRIPT_DIR}"
echo "  ./build-and-push.sh"
echo "  ./deploy-cloudrun.sh"
echo ""
