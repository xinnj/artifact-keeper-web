#!/bin/bash

# Deploy script for Outline
# This script:
# 1. Rsync project to remote server
# 2. Build and push Docker image (linux/amd64 via buildx)
# 3. Restart Kubernetes deployment

set -e  # Exit on error

# Load configuration from env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.env.remote.local"

SSH_OPTS="-o StrictHostKeyChecking=no -p ${REMOTE_PORT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}



# Step 1: Rsync project to remote server
step1_rsync() {
    echo_info "Step 1: Syncing project to remote server..."
    
    # Create remote directory
    echo_info "Creating remote directory..."
    ssh ${SSH_OPTS} \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p ${REMOTE_PATH}"
    
    # Sync project files to remote server using rsync
    echo_info "Syncing files to remote server (this may take a moment)..."
    rsync -avz --delete \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='.DS_Store' \
        --exclude='*.md' \
        --exclude='deploy.sh' \
        -e "ssh ${SSH_OPTS}" \
        ./ \
        "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"
    
    echo_info "Project synced successfully!"
}

# Step 2: Build and push Docker image
step2_build_push() {
    echo_info "Step 2: Building and pushing Docker image..."

    # Ensure docker buildx is available on the remote server
    echo_info "Checking docker buildx on remote server..."
    ssh ${SSH_OPTS} \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "docker buildx version" || {
        echo_error "docker buildx is not available on remote server. Please install Docker Buildx first."
        exit 1
    }

    local build_args=""
    [ -n "$APT_MIRROR" ] && build_args="$build_args --build-arg APT_MIRROR=$APT_MIRROR"
    [ -n "$YARN_REGISTRY" ] && build_args="$build_args --build-arg YARN_REGISTRY=$YARN_REGISTRY"

    echo_info "Building and pushing Docker image: ${DOCKER_IMAGE} (linux/amd64)"
    ssh ${SSH_OPTS} \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "cd ${REMOTE_PATH} && docker buildx build --platform linux/amd64 -f Dockerfile -t ${DOCKER_IMAGE} --push $build_args ."

    echo_info "Docker image built and pushed successfully!"
}

# Step 3: Restart Kubernetes deployment via rolling restart
K8S_WAIT_TIMEOUT="${K8S_WAIT_TIMEOUT:-120}"

step3_restart_k8s() {
    echo_info "Step 3: Restarting Kubernetes deployment..."

    # Check if kube config file exists
    if [ ! -f "$KUBE_CONFIG" ]; then
        echo_error "Kube config file not found: ${KUBE_CONFIG}"
        exit 1
    fi

    local KCTL="kubectl --kubeconfig=$KUBE_CONFIG -n $K8S_NAMESPACE"

    echo_info "Triggering rolling restart for deployment ${K8S_DEPLOYMENT} in namespace ${K8S_NAMESPACE}..."
    $KCTL rollout restart deployment "$K8S_DEPLOYMENT"

    # Wait for rollout to complete
    echo_info "Waiting for rollout to complete (timeout: ${K8S_WAIT_TIMEOUT}s)..."
    if $KCTL rollout status deployment "$K8S_DEPLOYMENT" --timeout="${K8S_WAIT_TIMEOUT}s"; then
        echo_info "Deployment ${K8S_DEPLOYMENT} restarted successfully!"
    else
        echo_error "Rollout for deployment ${K8S_DEPLOYMENT} failed or timed out"
        exit 1
    fi
}

# Main execution
main() {
    echo_info "=========================================="
    echo_info "Starting deployment of Outline"
    echo_info "=========================================="
    echo ""
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi

    # Execute steps
    step1_rsync
    echo ""
    
    step2_build_push
    echo ""
    
    step3_restart_k8s
    echo ""
    
    echo_info "=========================================="
    echo_info "Deployment completed successfully!"
    echo_info "=========================================="
}

# Run main function
main "$@"
