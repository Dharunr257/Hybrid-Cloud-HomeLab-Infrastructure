#!/bin/bash

# ==========================================================
# HCHI Deployment Engine v2
# Hybrid Cloud HomeLab Infrastructure
# ==========================================================

set -e

# ==========================================================
# CONFIGURATION
# ==========================================================

PLATFORM_ROOT="/mnt/homelab-storage/platform"
APPS_DIR="$PLATFORM_ROOT/apps"
DEPLOYMENTS_DIR="$PLATFORM_ROOT/deployments"
LOGS_DIR="$PLATFORM_ROOT/logs"

NPM_URL="http://192.168.1.10:81"
NPM_EMAIL="admin@example.com"
NPM_PASSWORD="admin@123"

# ==========================================================
# VALIDATE INPUT
# ==========================================================

if [ -z "$1" ]; then
    echo "Usage:"
    echo "deploy-app <git-repo-url>"
    exit 1
fi

REPO_URL=$1

# ==========================================================
# EXTRACT APP NAME
# ==========================================================

REPO_NAME=$(basename "$REPO_URL" .git)

LOWERCASE_APP_NAME=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')

APP_PATH="$APPS_DIR/$REPO_NAME"

LOG_FILE="$LOGS_DIR/${LOWERCASE_APP_NAME}.log"

mkdir -p "$LOGS_DIR"

# ==========================================================
# LOGGING FUNCTION
# ==========================================================

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

# ==========================================================
# START
# ==========================================================

log "=================================================="
log "HCHI Deployment Engine Started"
log "=================================================="

# ==========================================================
# CLONE REPOSITORY
# ==========================================================

if [ -d "$APP_PATH" ]; then
    log "ERROR: Application already exists."
    exit 1
fi

log "Cloning repository..."

git clone "$REPO_URL" "$APP_PATH"

cd "$APP_PATH"

# ==========================================================
# VALIDATE FILES
# ==========================================================

REQUIRED_FILES=(
    "Dockerfile"
    "deployment.json"
)

for file in "${REQUIRED_FILES[@]}"
do
    if [ ! -f "$file" ]; then
        log "ERROR: Missing required file -> $file"
        exit 1
    fi
done

log "Application structure validated."

# ==========================================================
# READ deployment.json
# ==========================================================

APP_NAME=$(jq -r '.app_name' deployment.json | tr '[:upper:]' '[:lower:]')
CONTAINER_NAME=$(jq -r '.container_name' deployment.json | tr '[:upper:]' '[:lower:]')
INTERNAL_DOMAIN=$(jq -r '.internal_domain' deployment.json)
CONTAINER_PORT=$(jq -r '.container_port' deployment.json)
HOST_PORT=$(jq -r '.host_port' deployment.json)
HEALTH_ENDPOINT=$(jq -r '.health_endpoint' deployment.json)
RESTART_POLICY=$(jq -r '.restart_policy' deployment.json)
NETWORK=$(jq -r '.network' deployment.json)

log "Application Name : $APP_NAME"
log "Container Name   : $CONTAINER_NAME"

# ==========================================================
# BUILD IMAGE
# ==========================================================

log "Building Docker image..."

docker build -t "$APP_NAME" . | tee -a "$LOG_FILE"

# ==========================================================
# REMOVE OLD CONTAINER
# ==========================================================

log "Removing old container if exists..."

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# ==========================================================
# DEPLOY CONTAINER
# ==========================================================

log "Deploying container..."

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart "$RESTART_POLICY" \
  --network "$NETWORK" \
  --network-alias "$CONTAINER_NAME" \
  -p "$HOST_PORT:$CONTAINER_PORT" \
  "$APP_NAME"

# ==========================================================
# WAIT FOR STARTUP
# ==========================================================

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
# VERIFY CONTAINER
# ==========================================================

if docker ps | grep -q "$CONTAINER_NAME"; then
    log "Container started successfully."
else
    log "ERROR: Container failed to start."
    docker logs "$CONTAINER_NAME"
    exit 1
fi

# ==========================================================
# AUTHENTICATE NGINX PROXY MANAGER
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
# CREATE PROXY HOST
# ==========================================================

log "Creating NGINX Proxy Host..."

RESPONSE=$(curl -s -X POST "$NPM_URL/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"domain_names\": [\"$INTERNAL_DOMAIN\"],
        \"forward_scheme\": \"http\",
        \"forward_host\": \"$CONTAINER_NAME\",
        \"forward_port\": $CONTAINER_PORT,
        \"access_list_id\": 0,
        \"certificate_id\": null,
        \"ssl_forced\": false,
        \"caching_enabled\": false,
        \"block_exploits\": true,
        \"allow_websocket_upgrade\": true,
        \"http2_support\": false,
        \"advanced_config\": \"\"
      }")

echo "$RESPONSE" | tee -a "$LOG_FILE"

# ==========================================================
# VERIFY PROXY CREATION
# ==========================================================

if echo "$RESPONSE" | grep -q '"error"'; then
    log "ERROR: Failed to create NGINX proxy host."
    exit 1
fi

log "NGINX proxy host configured successfully."

# ==========================================================
# SAVE DEPLOYMENT INFO
# ==========================================================

mkdir -p "$DEPLOYMENTS_DIR/$APP_NAME"

cp deployment.json "$DEPLOYMENTS_DIR/$APP_NAME/"

cat > "$DEPLOYMENTS_DIR/$APP_NAME/deployment-info.txt" <<EOF
Application Name : $APP_NAME
Repository       : $REPO_URL
Container Name   : $CONTAINER_NAME
Internal Domain  : $INTERNAL_DOMAIN
Host Port        : $HOST_PORT
Deployment Time  : $(date)
EOF

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
# CREATE DEPLOYMENT REGISTRY
# ==========================================================

DEPLOYMENT_FILE="/mnt/homelab-storage/platform/deployments/${APP_NAME}.json"

log "Creating deployment registry..."

cat > "$DEPLOYMENT_FILE" <<EOF
{
  "app_name": "$APP_NAME",
  "container_name": "$CONTAINER_NAME",
  "internal_domain": "$INTERNAL_DOMAIN",
  "container_port": $CONTAINER_PORT,
  "host_port": $HOST_PORT,
  "network": "$NETWORK",
  "health_endpoint": "$HEALTH_ENDPOINT",
  "repo_url": "$REPO_URL",
  "deployment_status": "$DEPLOYMENT_STATUS",
  "deployment_time": "$(date)",
  "docker_image": "$APP_NAME:latest"
}
EOF

log "Deployment registry created."

# ==========================================================
# COMPLETE
# ==========================================================

log "=================================================="
log "HCHI Deployment Successful"
log "=================================================="

log "Access URL:"
log "http://$INTERNAL_DOMAIN"

log "Logs:"
log "$LOG_FILE"

