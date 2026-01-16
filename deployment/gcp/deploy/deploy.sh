#!/bin/bash
# Convenience script - runs both deployment stages sequentially
# For independent execution, use build-and-push.sh and deploy-cloudrun.sh separately

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/project-config.sh"

echo "=========================================="
echo "n8n Complete Deployment (Both Stages)"
echo "=========================================="
echo ""
echo "This script runs both stages sequentially:"
echo "  Stage 1: Build and push Docker image"
echo "  Stage 2: Deploy to Cloud Run"
echo ""
echo "For independent execution, run stages separately:"
echo "  ./build-and-push.sh    # Stage 1 only"
echo "  ./deploy-cloudrun.sh   # Stage 2 only"
echo ""

# Check if we should use official image or build custom
USE_OFFICIAL="${USE_OFFICIAL_IMAGE:-false}"

if [ "${USE_OFFICIAL}" = "true" ]; then
  echo "Using official n8n image (skipping both stages)"
  echo ""
  echo "Note: Official image deployment is not yet implemented in push-and-deploy.sh"
  echo "Please use deploy-cloudrun.sh with USE_OFFICIAL_IMAGE=true for now"
  exit 1
else
  echo "Building custom n8n image with your changes"
  echo ""
  echo "⚠ Note: This requires Node.js >=22.16 and may take 5-10 minutes"
  echo ""
  
  # Check Node.js version
  NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1,2)
  REQUIRED_VERSION="22.16"
  
  if [ "$(printf '%s\n' "${REQUIRED_VERSION}" "${NODE_VERSION}" | sort -V | head -n1)" != "${REQUIRED_VERSION}" ]; then
    echo "⚠ Warning: Node.js version ${NODE_VERSION} is below required ${REQUIRED_VERSION}"
    echo ""
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "${CONTINUE}" != "yes" ]; then
      echo "Aborted. To use official image instead, run:"
      echo "  USE_OFFICIAL_IMAGE=true ./deploy.sh"
      exit 0
    fi
  fi
  
  # Stage 1: Build
  echo ""
  echo "=========================================="
  echo "Stage 1: Building application"
  echo "=========================================="
  cd "${SCRIPT_DIR}"
  ./build.sh
  
  if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Stage 1 failed!"
    echo ""
    echo "Fix build errors and run Stage 1 again:"
    echo "  ./build.sh"
    exit 1
  fi
  
  # Stage 2: Push and deploy
  echo ""
  echo "=========================================="
  echo "Stage 2: Pushing and deploying"
  echo "=========================================="
  ./push-and-deploy.sh
  
  if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Stage 2 failed!"
    echo ""
    echo "Fix deployment errors and run Stage 2 again:"
    echo "  ./deploy-cloudrun.sh"
    exit 1
  fi
fi

echo ""
echo "=========================================="
echo "Complete deployment finished!"
echo "=========================================="
