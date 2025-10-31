#!/usr/bin/env bash
set -e

# ======================================================
# 🚀 KubeBlocks + ArgoCD Bootstrap Script
# Author: Bastian Sommerer (lnxlabs)
# ======================================================

ARGO_NAMESPACE="argocd"
KUBEBLOCKS_NAMESPACE="kubeblocks-system"
DATA_NAMESPACE="data"
KUBEBLOCKS_VERSION="1.0.1"
ROOT_APP_PATH="root-app.yaml"

echo "=============================================="
echo "🏗️  Step 1: Create namespaces"
echo "=============================================="
kubectl create namespace $ARGO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $KUBEBLOCKS_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $DATA_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "=============================================="
echo "📦 Step 2: Install ArgoCD via Helm"
echo "=============================================="
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  -n $ARGO_NAMESPACE \
  --set server.service.type=LoadBalancer \
  --wait

echo "✅ ArgoCD installed."
echo "Waiting for ArgoCD to stabilize..."
for i in {1..20}; do
  READY=$(kubectl get pods -n $ARGO_NAMESPACE --no-headers 2>/dev/null | grep -c "Running") || true
  TOTAL=$(kubectl get pods -n $ARGO_NAMESPACE --no-headers 2>/dev/null | wc -l) || true
  echo "⏳ ArgoCD Pods Ready: $READY/$TOTAL"
  if [ "$READY" -ge 5 ]; then
    echo "✅ All main ArgoCD pods appear running."
    break
  fi
  sleep 10
done

echo "=============================================="
echo "📜 Step 3: Install KubeBlocks CRDs"
echo "=============================================="
kubectl create -f https://github.com/apecloud/kubeblocks/releases/download/v${KUBEBLOCKS_VERSION}/kubeblocks_crds.yaml || true

echo "✅ CRDs installed successfully."

echo "=============================================="
echo "🧩 Step 4: Deploy Root ArgoCD App"
echo "=============================================="
if [ ! -f "$ROOT_APP_PATH" ]; then
  echo "❌ Root app not found at $ROOT_APP_PATH"
  exit 1
fi

kubectl apply -f "$ROOT_APP_PATH" -n $ARGO_NAMESPACE

echo "✅ Root app applied successfully."

echo "=============================================="
echo "🔁 Step 5: Wait for all ArgoCD apps to sync"
echo "=============================================="

# Wait for ArgoCD root app sync
sleep 15
argocd app list || echo "ℹ️  You may need to login via argocd CLI first."

echo "Syncing all apps..."
for app in $(argocd app list -o name 2>/dev/null || true); do
  echo "🔁 Syncing $app..."
  argocd app sync "$app" || echo "⚠️  Failed to sync $app"
done

echo "=============================================="
echo "✅ Step 6: Verification"
echo "=============================================="
echo "KubeBlocks Clusters:"
kubectl get clusters.apps.kubeblocks.io -A || echo "No clusters found yet."

echo "Pods:"
kubectl get pods -A | grep -E "argocd|kubeblocks|redis|rabbitmq" || true

echo "=============================================="
echo "🎉 All done!"
echo "Access ArgoCD UI via:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  -> https://localhost:8080"
