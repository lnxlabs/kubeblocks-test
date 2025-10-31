#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✔ $1${NC}"; }
err()  { echo -e "${RED}✖ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}➜ $1${NC}"; }
step() { echo -e "${BLUE}═══ $1 ═══${NC}"; }

step "KubeBlocks Installation (Helmfile)"

# ----------------------------
# 1. Prerequisites Check
# ----------------------------
info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
  err "kubectl not found. Please install kubectl first."
fi

if ! command -v helm &> /dev/null; then
  err "helm not found. Please install helm first."
fi

if ! command -v helmfile &> /dev/null; then
  err "helmfile not found. Please install helmfile first."
fi

ok "All prerequisites found"

# ----------------------------
# 2. Install CRDs first
# ----------------------------
step "Installing KubeBlocks CRDs"
info "This must be done before deploying the operator..."

if kubectl get crd clusters.apps.kubeblocks.io &> /dev/null; then
  ok "CRDs already installed"
else
  info "Downloading and installing CRDs..."
  kubectl create -f https://github.com/apecloud/kubeblocks/releases/download/v1.0.1/kubeblocks_crds.yaml
  ok "CRDs installed successfully"
fi

# ----------------------------
# 3. Deploy via Helmfile
# ----------------------------
step "Deploying KubeBlocks and Addons"
info "Using helmfile to deploy kubeblocks, redis-addon, and rabbitmq-addon..."

cd "$(dirname "$0")"
helmfile sync

ok "KubeBlocks operator and addons deployed"

# ----------------------------
# 4. Wait for operator to be ready
# ----------------------------
step "Waiting for KubeBlocks operator"
info "This may take 1-2 minutes..."

kubectl wait --for=condition=available \
  --timeout=300s \
  deployment/kubeblocks \
  -n kubeblocks-system || err "Operator failed to become ready"

ok "KubeBlocks operator is ready"

# ----------------------------
# 5. Deploy Cluster Manifests
# ----------------------------
step "Deploying Redis and RabbitMQ clusters"
info "Creating namespace 'data'..."

kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f -

info "Applying Redis cluster..."
kubectl apply -f ../manifests/redis/cluster.yaml

info "Applying RabbitMQ cluster..."
kubectl apply -f ../manifests/rabbitmq/cluster.yaml

ok "Cluster manifests applied"

# ----------------------------
# 6. Wait for clusters to be ready
# ----------------------------
step "Waiting for clusters to become ready"
info "This may take 2-5 minutes..."

echo ""
info "Waiting for Redis cluster..."
kubectl wait --for=jsonpath='{.status.phase}'=Running \
  --timeout=300s \
  cluster/redis-cluster \
  -n data 2>/dev/null || true

info "Waiting for RabbitMQ cluster..."
kubectl wait --for=jsonpath='{.status.phase}'=Running \
  --timeout=300s \
  cluster/rabbitmq-cluster \
  -n data 2>/dev/null || true

echo ""
ok "Installation complete!"

# ----------------------------
# Summary
# ----------------------------
echo ""
step "Summary"
echo ""
echo "KubeBlocks has been successfully installed via Helmfile. You can now:"
echo ""
echo "  📋 Check cluster status:"
echo "     kubectl get clusters -n data"
echo ""
echo "  🔍 View pods:"
echo "     kubectl get pods -n data"
echo ""
echo "  🧪 Run tests:"
echo "     ../test-kubeblocks-helmfile.sh"
echo ""
echo "  📖 View logs:"
echo "     kubectl logs -n kubeblocks-system deploy/kubeblocks"
echo ""
