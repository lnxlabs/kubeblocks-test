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
# 1. Check ArgoCD
# ----------------------------
info "Checking ArgoCD..."
if argocd app sync root --timeout 600 >/dev/null 2>&1; then
  ok "ArgoCD apps synced"
else
  err "ArgoCD sync failed"
fi

# ----------------------------
# 2. Check Pods
# ----------------------------
info "Checking pods..."
if kubectl get pods -A | grep -Eq "CrashLoopBackOff|Error|Pending"; then
  err "Some pods not healthy"
else
  ok "All pods running"
fi

# ----------------------------
# 3. RabbitMQ Test
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
# 4. Redis Test (mit Passwort)
# ----------------------------
info "Testing Redis..."
REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -o name | grep redis || true)
if [ -z "$REDIS_POD" ]; then
  err "No Redis pod found"
else
  # Passwort aus Secret lesen
  REDIS_SECRET="redis-cluster-redis-account-default"
  REDIS_PASS=$(kubectl get secret -n "$NAMESPACE" "$REDIS_SECRET" -o jsonpath='{.data.password}' | base64 --decode)

  if [ -z "$REDIS_PASS" ]; then
    err "Redis password not found in secret"
  else
    if kubectl exec -n "$NAMESPACE" "$REDIS_POD" -c redis -- sh -c "redis-cli -a '$REDIS_PASS' ping | grep -q PONG"; then
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
