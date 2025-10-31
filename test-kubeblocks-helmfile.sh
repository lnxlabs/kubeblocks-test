#!/bin/bash
set -euo pipefail

NAMESPACE=${1:-data}
START=$(date +%s)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=()

ok()   { echo -e "${GREEN}✔ $1${NC}"; }
err()  { echo -e "${RED}✖ $1${NC}"; FAILED+=("$1"); }
info() { echo -e "${YELLOW}➜ $1${NC}"; }

# ----------------------------
# 1. Check KubeBlocks Operator
# ----------------------------
info "Checking KubeBlocks operator..."
if kubectl get deployment kubeblocks -n kubeblocks-system &>/dev/null; then
  if kubectl get deployment kubeblocks -n kubeblocks-system -o jsonpath='{.status.availableReplicas}' | grep -q "1"; then
    ok "KubeBlocks operator is running"
  else
    err "KubeBlocks operator not ready"
  fi
else
  err "KubeBlocks operator not found"
fi

# ----------------------------
# 2. Check Pods
# ----------------------------
info "Checking pods in namespace '$NAMESPACE'..."
if kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -Eq "CrashLoopBackOff|Error|Pending"; then
  err "Some pods not healthy in namespace $NAMESPACE"
else
  POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$POD_COUNT" -gt 0 ]; then
    ok "All pods running in namespace $NAMESPACE ($POD_COUNT pods)"
  else
    err "No pods found in namespace $NAMESPACE"
  fi
fi

# ----------------------------
# 3. Check Clusters
# ----------------------------
info "Checking KubeBlocks clusters..."
REDIS_STATUS=$(kubectl get cluster redis-cluster -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
RABBITMQ_STATUS=$(kubectl get cluster rabbitmq-cluster -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [ "$REDIS_STATUS" = "Running" ]; then
  ok "Redis cluster is Running"
else
  err "Redis cluster status: $REDIS_STATUS"
fi

if [ "$RABBITMQ_STATUS" = "Running" ]; then
  ok "RabbitMQ cluster is Running"
else
  err "RabbitMQ cluster status: $RABBITMQ_STATUS"
fi

# ----------------------------
# 4. RabbitMQ Test
# ----------------------------
info "Testing RabbitMQ..."
RABBIT_POD=$(kubectl get pods -n "$NAMESPACE" -o name | grep rabbitmq || true)
if [ -z "$RABBIT_POD" ]; then
  err "No RabbitMQ pod found"
else
  if kubectl exec -n "$NAMESPACE" "$RABBIT_POD" -- rabbitmqctl cluster_status >/dev/null 2>&1; then
    ok "RabbitMQ cluster healthy"
  else
    err "RabbitMQ cluster test failed"
  fi
fi

# ----------------------------
# 5. Redis Test (mit Passwort)
# ----------------------------
info "Testing Redis..."
REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -o name | grep redis || true)
if [ -z "$REDIS_POD" ]; then
  err "No Redis pod found"
else
  # Passwort aus Secret lesen
  REDIS_SECRET="redis-cluster-redis-account-default"
  REDIS_PASS=$(kubectl get secret -n "$NAMESPACE" "$REDIS_SECRET" -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode || echo "")

  if [ -z "$REDIS_PASS" ]; then
    err "Redis password not found in secret"
  else
    if kubectl exec -n "$NAMESPACE" "$REDIS_POD" -c redis -- sh -c "redis-cli -a '$REDIS_PASS' ping 2>/dev/null | grep -q PONG"; then
      ok "Redis responded to authenticated PING"
    else
      err "Redis PING with password failed"
    fi
  fi
fi

# ----------------------------
# Summary
# ----------------------------
echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  ok "All tests passed in $(( $(date +%s) - START ))s 🚀"
else
  err "${#FAILED[@]} test(s) failed:"
  for f in "${FAILED[@]}"; do echo "   - $f"; done
  exit 1
fi
