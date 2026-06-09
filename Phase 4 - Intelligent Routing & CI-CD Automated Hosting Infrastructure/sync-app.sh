#!/bin/bash

# ==========================================================
# HCHI Sync Engine v2
# ==========================================================

set -e

# ==========================================================
# VALIDATE INPUT
# ==========================================================

if [ -z "$1" ]; then
    echo "Usage:"
    echo "sync-app <app-name>"
    exit 1
fi

APP_FOLDER=$1

PLATFORM_ROOT="/mnt/homelab-storage/platform"
APP_PATH="$PLATFORM_ROOT/apps/$APP_FOLDER"
LOGS_DIR="$PLATFORM_ROOT/logs"

LOWERCASE_APP_NAME=$(echo "$APP_FOLDER" | tr '[:upper:]' '[:lower:]')

LOG_FILE="$LOGS_DIR/${LOWERCASE_APP_NAME}-sync.log"

mkdir -p "$LOGS_DIR"

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

# ==========================================================
# VALIDATE APP
# ==========================================================

if [ ! -d "$APP_PATH" ]; then
    log "ERROR: App not found -> $APP_FOLDER"
    exit 1
fi

cd "$APP_PATH"

# ==========================================================
# READ deployment.json
# ==========================================================

APP_NAME=$(jq -r '.app_name' deployment.json | tr '[:upper:]' '[:lower:]')
CONTAINER_NAME=$(jq -r '.container_name' deployment.json | tr '[:upper:]' '[:lower:]')
CONTAINER_PORT=$(jq -r '.container_port' deployment.json)
HOST_PORT=$(jq -r '.host_port' deployment.json)
RESTART_POLICY=$(jq -r '.restart_policy' deployment.json)
NETWORK=$(jq -r '.network' deployment.json)

# ==========================================================
# START
# ==========================================================

log "=================================================="
log "HCHI Sync Started"
log "=================================================="

# ==========================================================
# PULL LATEST CODE
# ==========================================================

log "Pulling latest code..."

git pull origin main | tee -a "$LOG_FILE"

# ==========================================================
# BUILD IMAGE
# ==========================================================

log "Building Docker image..."

docker build -t "$APP_NAME" . | tee -a "$LOG_FILE"

# ==========================================================
# REMOVE OLD CONTAINER
# ==========================================================

log "Stopping old container..."

docker stop "$CONTAINER_NAME" 2>/dev/null || true

docker rm "$CONTAINER_NAME" 2>/dev/null || true

# ==========================================================
# DEPLOY UPDATED CONTAINER
# ==========================================================

log "Deploying updated container..."

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart "$RESTART_POLICY" \
  --network "$NETWORK" \
  --network-alias "$CONTAINER_NAME" \
  -p "$HOST_PORT:$CONTAINER_PORT" \
  "$APP_NAME"


sleep 5

# ==========================================================
# HEALTH CHECK
# ==========================================================

log "Performing health check..."

HEALTH_URL="http://localhost:${HOST_PORT}${HEALTH_ENDPOINT}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL")

if [ "$HTTP_CODE" = "200" ]; then

    DEPLOYMENT_STATUS="healthy"

    log "Health check passed."

else

    DEPLOYMENT_STATUS="unhealthy"

    log "WARNING: Health check failed."

fi

# ==========================================================
# VERIFY
# ==========================================================

if docker ps | grep -q "$CONTAINER_NAME"; then
    log "Container deployed successfully."
else
    log "ERROR: Deployment failed."
    docker logs "$CONTAINER_NAME"
    exit 1
fi

# ==========================================================
# HEALTH CHECK
# ==========================================================

log "Performing health check..."

HEALTH_URL="http://localhost:${HOST_PORT}${HEALTH_ENDPOINT}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL")

if [ "$HTTP_CODE" = "200" ]; then

    DEPLOYMENT_STATUS="healthy"

    log "Health check passed."

else

    DEPLOYMENT_STATUS="unhealthy"

    log "WARNING: Health check failed."

fi

# ==========================================================
# UPDATE DEPLOYMENT REGISTRY
# ==========================================================

DEPLOYMENT_FILE="/mnt/homelab-storage/platform/deployments/${APP_NAME}.json"

log "Updating deployment registry..."

cat > "$DEPLOYMENT_FILE" <<EOF
{
  "app_name": "$APP_NAME",
  "container_name": "$CONTAINER_NAME",
  "internal_domain": "$INTERNAL_DOMAIN",
  "container_port": $CONTAINER_PORT,
  "host_port": $HOST_PORT,
  "network": "$NETWORK",
  "health_endpoint": "$HEALTH_ENDPOINT",
  "deployment_status": "$DEPLOYMENT_STATUS",
  "last_sync_time": "$(date)",
  "docker_image": "$APP_NAME:latest"
}
EOF

log "Deployment registry updated."

log "=================================================="
log "HCHI Sync Successful"
log "=================================================="

