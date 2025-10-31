#!/bin/bash
set -euo pipefail

echo "🚀 Starting KubeBlocks integration test..."
START=$(date +%s)

# Colors for pretty output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function check_argocd() {
  echo -e "${YELLOW}🧩 Checking ArgoCD applications...${NC}"
  argocd app list || { echo -e "${RED}❌ Failed to list ArgoCD apps${NC}"; exit 1; }

  echo -e "${YELLOW}🔁 Syncing all apps...${NC}"
  argocd app sync --all --prune --timeout 600 || {
    echo -e "${RED}❌ Some ArgoCD apps failed to sync${NC}"
    argocd app list -o wide
    exit 1
  }

  if argocd app list -o wide | grep -E "OutOfSync|Missing"; then
    echo -e "${RED}❌ Some apps are OutOfSync or Missing${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ All ArgoCD apps synced and healthy${NC}"
}

function check_pods() {
  echo -e "${YELLOW}🔍 Checking pod health...${NC}"
  kubectl get pods -A

  if kubectl get pods -A | grep -E "CrashLoopBackOff|Error|Pending"; then
    echo -e "${RED}❌ Some pods are not running cleanly${NC}"
    kubectl get pods -A | grep -E "CrashLoopBackOff|Error|Pending"
    exit 1
  fi

  echo -e "${GREEN}✅ All pods running${NC}"
}

function test_rabbitmq() {
  echo -e "${YELLOW}🐇 Testing RabbitMQ cluster...${NC}"
  RABBIT_POD=$(kubectl get pod -n data -l "app.kubernetes.io/name=rabbitmq" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [ -z "$RABBIT_POD" ]; then
    echo -e "${RED}❌ RabbitMQ pod not found in namespace data${NC}"
    return 1
  fi

  kubectl exec -n data "$RABBIT_POD" -- rabbitmqctl cluster_status || {
    echo -e "${RED}❌ RabbitMQ cluster test failed${NC}"
    return 1
  }

  echo -e "${GREEN}✅ RabbitMQ cluster healthy${NC}"
}

function test_redis() {
  echo -e "${YELLOW}🧱 Testing Redis cluster...${NC}"
  REDIS_POD=$(kubectl get pod -n data -l "app.kubernetes.io/name=redis" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [ -z "$REDIS_POD" ]; then
    echo -e "${RED}❌ Redis pod not found in namespace data${NC}"
    return 1
  fi

  kubectl exec -n data "$REDIS_POD" -- redis-cli ping | grep -q "PONG" || {
    echo -e "${RED}❌ Redis ping failed${NC}"
    return 1
  }

  echo -e "${GREEN}✅ Redis responded to PING${NC}"
}

function summary() {
  END=$(date +%s)
  echo -e "\n${GREEN}🎉 All tests passed successfully in $((END - START))s${NC}"
}

# --- Run all tests ---
check_argocd
check_pods
test_rabbitmq
test_redis
summary
