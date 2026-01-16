#!/bin/bash
# Stage 1: Build n8n application
# This script only builds the application, does not create Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "=========================================="
echo "Stage 1: Building n8n application"
echo "=========================================="
echo ""

# Check if pnpm is available
if ! command -v pnpm &> /dev/null; then
  echo "Error: pnpm is not installed"
  echo "Install with: npm install -g pnpm"
  exit 1
fi

# Check if we're in the repository root
cd "${REPO_ROOT}"
if [ ! -f "package.json" ]; then
  echo "Error: Not in n8n repository root. Expected package.json not found."
  exit 1
fi

# Check Node.js version
NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1,2)
REQUIRED_VERSION="22.16"

if [ "$(printf '%s\n' "${REQUIRED_VERSION}" "${NODE_VERSION}" | sort -V | head -n1)" != "${REQUIRED_VERSION}" ]; then
  echo "⚠ Warning: Node.js version ${NODE_VERSION} is below required ${REQUIRED_VERSION}"
  echo "Build may fail or produce warnings"
  echo ""
fi

# Build the application
echo "Building n8n application..."
echo "This may take 5-10 minutes..."
echo ""

pnpm build:deploy

if [ ! -d "compiled" ]; then
  echo "❌ Error: Build failed. 'compiled' directory not found."
  exit 1
fi

echo ""
echo "=========================================="
echo "Stage 1 completed successfully!"
echo "=========================================="
echo ""
echo "✓ Application built in: ${REPO_ROOT}/compiled"
echo ""
echo "Next step: Push and deploy"
echo "  cd ${SCRIPT_DIR}"
echo "  ./push-and-deploy.sh"
echo ""
