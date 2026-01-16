#!/bin/bash
# GCP Project Configuration for n8n deployment
# This file contains all GCP project-specific settings

set -e

# GCP Project Settings
export GCP_PROJECT="docmost-484110"
export GCP_REGION="europe-west1"
export GCP_ZONE="europe-west1-c"

# Service Account
export SERVICE_ACCOUNT="584964349468-compute@developer.gserviceaccount.com"

# Existing Infrastructure Resources
export CLOUD_SQL_INSTANCE="docmost-484110:europe-west1:docmost-2"
export CLOUD_SQL_CONNECTION_NAME="docmost-484110:europe-west1:docmost-2"
export REDIS_INSTANCE="docmost"
export REDIS_HOST="10.227.192.35"
export REDIS_PORT="6379"
export STORAGE_BUCKET="ja-docmost"

# Database Configuration
export DB_NAME="n8n"
export DB_USER="n8n_user"
# DB_PASSWORD will be set in secrets

# Redis Configuration
export REDIS_DB_INDEX="1"  # Use DB 1 for n8n (docmost uses DB 0)

# Cloud Run Configuration
export CLOUD_RUN_SERVICE="n8n"
export CLOUD_RUN_CPU="2"
export CLOUD_RUN_MEMORY="2Gi"
export CLOUD_RUN_MIN_INSTANCES="0"
export CLOUD_RUN_MAX_INSTANCES="10"
export CLOUD_RUN_TIMEOUT="300"
export CLOUD_RUN_CONCURRENCY="80"
export CLOUD_RUN_PORT="5678"

# Container Registry
export GCR_REPOSITORY="gcr.io/${GCP_PROJECT}/n8n"
export IMAGE_TAG="${IMAGE_TAG:-latest}"

# Secret Manager prefix for n8n secrets
export SECRET_PREFIX="n8n-"

# Load this configuration
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  # Script is being executed directly
  echo "GCP Project Configuration:"
  echo "  Project: ${GCP_PROJECT}"
  echo "  Region: ${GCP_REGION}"
  echo "  Cloud SQL: ${CLOUD_SQL_INSTANCE}"
  echo "  Redis: ${REDIS_INSTANCE} (${REDIS_HOST}:${REDIS_PORT})"
  echo "  Storage: ${STORAGE_BUCKET}"
  echo "  Cloud Run Service: ${CLOUD_RUN_SERVICE}"
fi
