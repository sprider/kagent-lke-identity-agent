#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${HOME}/.kube/kagent-identity-config"

export KUBECONFIG="${KUBECONFIG_PATH}"

echo "=== Ensuring demo namespace and broken app are applied ==="
kubectl apply -f "${REPO_ROOT}/k8s/00-namespace.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/10-broken-app.yaml"

kubectl patch svc frontend-svc -n demo --type merge \
  -p '{"spec":{"selector":{"app":"frontend-BROKEN"}}}'

echo "=== Waiting for zero endpoints ==="
for i in {1..30}; do
  EPS=$(kubectl get endpoints frontend-svc -n demo -o jsonpath='{.subsets}' 2>/dev/null || true)
  if [[ -z "${EPS}" || "${EPS}" == "null" ]]; then
    break
  fi
  sleep 2
done

echo ""
kubectl get svc frontend-svc -n demo
kubectl get endpoints frontend-svc -n demo
echo ""
echo "Broken Service is ready (selector mismatch → 0 endpoints)."
