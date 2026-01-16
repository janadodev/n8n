#!/bin/bash
# Build n8n Docker image and push to Google Container Registry
# This script builds the application and creates a Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${SCRIPT_DIR}/../config/project-config.sh"

echo "=========================================="
echo "Building and pushing n8n Docker image"
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

# Get git information for tagging
cd "${REPO_ROOT}"
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build n8n application
echo ""
echo "Step 1: Building n8n application..."
cd "${REPO_ROOT}"

if [ ! -f "package.json" ]; then
  echo "Error: Not in n8n repository root. Expected package.json not found."
  exit 1
fi

# Check if pnpm is available
if ! command -v pnpm &> /dev/null; then
  echo "Error: pnpm is not installed"
  echo "Install with: npm install -g pnpm"
  exit 1
fi

# Build the application
echo "Running: pnpm build:deploy"
pnpm build:deploy

if [ ! -d "compiled" ]; then
  echo "Error: Build failed. 'compiled' directory not found."
  exit 1
fi

echo "✓ Application built successfully"

# Build Docker image
echo ""
echo "Step 2: Building Docker image..."

# Determine N8N version from package.json or use git tag
N8N_VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "snapshot")

# Build the image
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
echo "Step 3: Pushing image to Google Container Registry..."

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
echo "Step 4: Verifying image..."
if gcloud container images describe "${IMAGE_NAME}" --project="${GCP_PROJECT}" &>/dev/null; then
  echo "✓ Image verified in GCR"
  
  # Get image digest
  IMAGE_DIGEST=$(gcloud container images describe "${IMAGE_NAME}" --project="${GCP_PROJECT}" --format="value(image_summary.fully_qualified_digest)")
  echo "  Image digest: ${IMAGE_DIGEST}"
else
  echo "⚠ Warning: Could not verify image in GCR"
fi

echo ""
echo "=========================================="
echo "Build and push completed successfully!"
echo "=========================================="
echo ""
echo "Image: ${IMAGE_NAME}"
echo "  Commit: ${GIT_COMMIT}"
echo "  Branch: ${GIT_BRANCH}"
echo "  Version: ${N8N_VERSION}"
echo ""
echo "✓ Image is ready in GCR: ${GCR_REPOSITORY}:${IMAGE_TAG}"
echo ""
echo "Next step: Deploy to Cloud Run"
echo "  cd ${SCRIPT_DIR}"
echo "  ./deploy-cloudrun.sh"
echo ""
echo "Or use a specific image tag:"
echo "  IMAGE_TAG=${IMAGE_TAG} ./deploy-cloudrun.sh"
echo ""