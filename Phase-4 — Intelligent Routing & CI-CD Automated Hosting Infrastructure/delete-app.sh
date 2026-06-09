#!/bin/bash

# ==========================================================
# HCHI Application Removal Engine
# ==========================================================

set -e

# ==========================================================
# VALIDATE INPUT
# ==========================================================

if [ -z "$1" ]; then
    echo "Usage:"
    echo "delete-app <app-folder-name>"
    exit 1
fi

APP_FOLDER=$1

# ==========================================================
# PLATFORM CONFIG
# ==========================================================

PLATFORM_ROOT="/mnt/homelab-storage/platform"

APPS_DIR="$PLATFORM_ROOT/apps"
DEPLOYMENTS_DIR="$PLATFORM_ROOT/deployments"
LOGS_DIR="$PLATFORM_ROOT/logs"

APP_PATH="$APPS_DIR/$APP_FOLDER"

# ==========================================================
# NGINX PROXY MANAGER CONFIG
# ==========================================================

NPM_URL="http://192.168.1.10:81"
NPM_EMAIL="admin@example.com"
NPM_PASSWORD="admin@123"

# ==========================================================
# LOGGING
# ==========================================================

LOWERCASE_APP_NAME=$(echo "$APP_FOLDER" | tr '[:upper:]' '[:lower:]')

LOG_FILE="$LOGS_DIR/${LOWERCASE_APP_NAME}-delete.log"

mkdir -p "$LOGS_DIR"

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

# ==========================================================
# VALIDATE APP EXISTS
# ==========================================================

if [ ! -d "$APP_PATH" ]; then
    log "ERROR: Application not found -> $APP_FOLDER"
    exit 1
fi

cd "$APP_PATH"

# ==========================================================
# VALIDATE deployment.json
# ==========================================================

if [ ! -f "deployment.json" ]; then
    log "ERROR: deployment.json missing"
    exit 1
fi

# ==========================================================
# READ deployment.json
# ==========================================================

APP_NAME=$(jq -r '.app_name' deployment.json | tr '[:upper:]' '[:lower:]')

CONTAINER_NAME=$(jq -r '.container_name' deployment.json | tr '[:upper:]' '[:lower:]')

INTERNAL_DOMAIN=$(jq -r '.internal_domain' deployment.json)

# ==========================================================
# START
# ==========================================================

log "=================================================="
log "HCHI Application Removal Started"
log "=================================================="

log "Application Name : $APP_NAME"
log "Container Name   : $CONTAINER_NAME"
log "Internal Domain  : $INTERNAL_DOMAIN"

# ==========================================================
# STOP CONTAINER
# ==========================================================

log "Stopping container..."

docker stop "$CONTAINER_NAME" 2>/dev/null || true

# ==========================================================
# REMOVE CONTAINER
# ==========================================================

log "Removing container..."

docker rm "$CONTAINER_NAME" 2>/dev/null || true

# ==========================================================
# REMOVE IMAGE
# ==========================================================

log "Removing Docker image..."

docker rmi "$APP_NAME" 2>/dev/null || true

# ==========================================================
# AUTHENTICATE NPM
# ==========================================================

log "Authenticating with NGINX Proxy Manager..."

TOKEN=$(curl -s -X POST "$NPM_URL/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{
        \"identity\": \"$NPM_EMAIL\",
        \"secret\": \"$NPM_PASSWORD\"
      }" | jq -r '.token')

if [ "$TOKEN" == "null" ]; then
    log "ERROR: Failed to authenticate with NPM."
    exit 1
fi

# ==========================================================
# FIND PROXY HOST ID
# ==========================================================

log "Finding NGINX proxy host..."

PROXY_HOST_ID=$(curl -s -X GET "$NPM_URL/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" | jq -r ".[] | select(.domain_names[] == \"$INTERNAL_DOMAIN\") | .id")

# ==========================================================
# DELETE PROXY HOST
# ==========================================================

if [ -n "$PROXY_HOST_ID" ]; then

    log "Deleting NGINX proxy host..."

    curl -s -X DELETE "$NPM_URL/api/nginx/proxy-hosts/$PROXY_HOST_ID" \
      -H "Authorization: Bearer $TOKEN"

    log "NGINX proxy host removed."

else

    log "No proxy host found."

fi

# ==========================================================
# REMOVE APPLICATION FILES
# ==========================================================

log "Removing application source files..."

rm -rf "$APP_PATH"

# ==========================================================
# REMOVE DEPLOYMENT REGISTRY
# ==========================================================

DEPLOYMENT_FILE="/mnt/homelab-storage/platform/deployments/${APP_NAME}.json"

log "Removing deployment registry..."

if [ -f "$DEPLOYMENT_FILE" ]; then

    rm -f "$DEPLOYMENT_FILE"

    log "Deployment registry removed."

else

    log "No deployment registry found."

fi

# ==========================================================
# CLEAN DANGLING IMAGES
# ==========================================================

log "Cleaning unused Docker images..."

docker image prune -f

# ==========================================================
# COMPLETE
# ==========================================================

log "=================================================="
log "HCHI Application Removal Complete"
log "=================================================="

log "Application removed successfully."
