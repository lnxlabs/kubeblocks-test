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
warn() { echo -e "${RED}⚠ $1${NC}"; }

step "KubeBlocks Uninstall (Helmfile)"

# ----------------------------
# 1. Delete cluster manifests first
# ----------------------------
step "Deleting Redis and RabbitMQ clusters"

if kubectl get namespace data &> /dev/null; then
  info "Deleting Redis cluster..."
  kubectl delete -f ../manifests/redis/cluster.yaml --ignore-not-found=true --wait=false 2>/dev/null || true

  info "Deleting RabbitMQ cluster..."
  kubectl delete -f ../manifests/rabbitmq/cluster.yaml --ignore-not-found=true --wait=false 2>/dev/null || true

  # Remove finalizers from clusters to speed up deletion
  info "Removing finalizers from clusters..."
  kubectl patch cluster redis-cluster -n data -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  kubectl patch cluster rabbitmq-cluster -n data -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

  ok "Cluster manifests deleted"
else
  info "Namespace 'data' not found, skipping cluster deletion"
fi

# ----------------------------
# 2. Delete Helm releases via Helmfile
# ----------------------------
step "Deleting Helm releases"
info "Using helmfile to destroy releases..."

cd "$(dirname "$0")"
helmfile destroy 2>/dev/null || info "No helmfile releases to destroy"
ok "Helmfile releases destroyed"

# ----------------------------
# 3. Delete namespaces
# ----------------------------
step "Deleting namespaces"

info "Deleting namespace 'data'..."
kubectl delete namespace data --wait=false --ignore-not-found=true 2>/dev/null || true

# Remove finalizers from namespace if stuck
sleep 2
if kubectl get namespace data &> /dev/null; then
  info "Namespace stuck, removing finalizers..."
  kubectl patch namespace data -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  kubectl delete namespace data --grace-period=0 --force 2>/dev/null || true
fi
ok "Namespace 'data' deleted"

info "Deleting namespace 'kubeblocks-system'..."
kubectl delete namespace kubeblocks-system --wait=false --ignore-not-found=true 2>/dev/null || true

# Remove finalizers from namespace if stuck
sleep 2
if kubectl get namespace kubeblocks-system &> /dev/null; then
  info "Namespace stuck, removing finalizers..."
  kubectl patch namespace kubeblocks-system -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  kubectl delete namespace kubeblocks-system --grace-period=0 --force 2>/dev/null || true
fi
ok "Namespace 'kubeblocks-system' deleted"

# ----------------------------
# Summary
# ----------------------------
echo ""
step "Uninstall Complete"
echo ""
ok "KubeBlocks has been successfully removed"
echo ""
echo "You can reinstall anytime with:"
echo "  cd helmfile && ./install.sh"
echo ""
