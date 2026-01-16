#!/bin/bash
# Environment Variables Configuration for n8n
# This file defines all environment variables that will be stored in Secret Manager
# Compatible with bash 3.2+ (macOS default)

set -e

# Source project configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/project-config.sh"

# Function to generate encryption key
generate_encryption_key() {
  openssl rand -base64 32
}

# Function to get environment variable value
# Usage: get_env_var "VAR_NAME"
get_env_var() {
  local var_name="$1"
  case "$var_name" in
    # App Configuration
    "N8N_PROTOCOL") echo "https" ;;
    "N8N_PORT") echo "5678" ;;
    "NODE_ENV") echo "production" ;;
    "N8N_METRICS") echo "true" ;;
    "N8N_DIAGNOSTICS_ENABLED") echo "false" ;;
    
    # Database Configuration
    "DB_TYPE") echo "postgresdb" ;;
    "DB_POSTGRESDB_HOST") echo "/cloudsql/${CLOUD_SQL_CONNECTION_NAME}" ;;
    "DB_POSTGRESDB_DATABASE") echo "${DB_NAME}" ;;
    "DB_POSTGRESDB_USER") echo "${DB_USER}" ;;
    "DB_POSTGRESDB_PASSWORD") echo "${DB_PASSWORD:-}" ;;
    "DB_POSTGRESDB_PORT") echo "5432" ;;
    
    # Redis Configuration
    "QUEUE_BULL_REDIS_HOST") echo "${REDIS_HOST}" ;;
    "QUEUE_BULL_REDIS_PORT") echo "${REDIS_PORT}" ;;
    "QUEUE_BULL_REDIS_DB") echo "${REDIS_DB_INDEX}" ;;
    "QUEUE_BULL_REDIS_PASSWORD") echo "${REDIS_PASSWORD:-}" ;;
    "EXECUTIONS_MODE") echo "queue" ;;
    
    # Cloud Storage Configuration
    "N8N_DEFAULT_BINARY_DATA_MODE") echo "s3" ;;
    "N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME") echo "${STORAGE_BUCKET}" ;;
    "N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION") echo "${GCP_REGION}" ;;
    "N8N_EXTERNAL_STORAGE_S3_HOST") echo "https://storage.googleapis.com" ;;
    "N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY") echo "${GCS_ACCESS_KEY:-}" ;;
    "N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET") echo "${GCS_SECRET_KEY:-}" ;;
    
    # Security Configuration
    "N8N_ENCRYPTION_KEY") echo "${N8N_ENCRYPTION_KEY:-}" ;;
    
    *) echo "" ;;
  esac
}

# Function to get all environment variable names
get_all_env_var_names() {
  echo "N8N_PROTOCOL
N8N_PORT
NODE_ENV
N8N_METRICS
N8N_DIAGNOSTICS_ENABLED
DB_TYPE
DB_POSTGRESDB_HOST
DB_POSTGRESDB_DATABASE
DB_POSTGRESDB_USER
DB_POSTGRESDB_PASSWORD
DB_POSTGRESDB_PORT
QUEUE_BULL_REDIS_HOST
QUEUE_BULL_REDIS_PORT
QUEUE_BULL_REDIS_DB
QUEUE_BULL_REDIS_PASSWORD
EXECUTIONS_MODE
N8N_DEFAULT_BINARY_DATA_MODE
N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME
N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION
N8N_EXTERNAL_STORAGE_S3_HOST
N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY
N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET
N8N_ENCRYPTION_KEY"
}

# Function to check if a variable requires manual input
requires_manual_input() {
  local var_name="$1"
  local value=$(get_env_var "$var_name")
  
  if [ -z "$value" ]; then
    return 0  # Requires manual input
  fi
  
  return 1  # Does not require manual input
}

# Export functions for use in other scripts
export -f get_all_env_var_names
export -f get_env_var
export -f requires_manual_input
export -f generate_encryption_key
