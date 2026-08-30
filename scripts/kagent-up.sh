#!/usr/bin/env bash
set -euo pipefail

: "${OPENAI_API_KEY:?OPENAI_API_KEY must be set}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${HOME}/.kube/kagent-identity-config"
SECRET_FILE="${REPO_ROOT}/.keycloak-client-secret"

export KUBECONFIG="${KUBECONFIG_PATH}"
export KUBE_CONFIG_PATH="${KUBECONFIG_PATH}"

"${REPO_ROOT}/scripts/keycloak-config.sh"

if [[ ! -f "${SECRET_FILE}" ]]; then
  echo "ERROR: Keycloak client secret file not found: ${SECRET_FILE}"
  exit 1
fi

KEYCLOAK_CLIENT_SECRET="$(cat "${SECRET_FILE}")"
if [[ -z "${KEYCLOAK_CLIENT_SECRET}" ]]; then
  echo "ERROR: Keycloak client secret is empty"
  exit 1
fi

echo "=== Waiting for Keycloak LoadBalancer IP ==="
cd "${REPO_ROOT}/terraform"
for i in {1..60}; do
  KEYCLOAK_URL="$(terraform output -raw keycloak_url 2>/dev/null || true)"
  if [[ -n "${KEYCLOAK_URL}" && "${KEYCLOAK_URL}" != "LoadBalancer IP not yet assigned" ]]; then
    break
  fi
  echo "Waiting for Keycloak LoadBalancer IP... ($i/60)"
  sleep 5
done

if [[ -z "${KEYCLOAK_URL}" || "${KEYCLOAK_URL}" == "LoadBalancer IP not yet assigned" ]]; then
  echo "ERROR: Keycloak LoadBalancer IP did not become available."
  echo "Check: kubectl get svc keycloak -n keycloak"
  exit 1
fi

KEYCLOAK_BASE="${KEYCLOAK_URL%:80}"
KEYCLOAK_ISSUER_URL="${KEYCLOAK_BASE}/realms/kagent-demo"
echo "Keycloak issuer URL: ${KEYCLOAK_ISSUER_URL}"
cd "${REPO_ROOT}"

if [[ -f "${REPO_ROOT}/.oauth2-cookie-secret" ]]; then
  OAUTH2_COOKIE_SECRET="$(cat "${REPO_ROOT}/.oauth2-cookie-secret")"
else
  OAUTH2_COOKIE_SECRET="$(openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_' | cut -c1-32)"
  echo -n "${OAUTH2_COOKIE_SECRET}" > "${REPO_ROOT}/.oauth2-cookie-secret"
  chmod 600 "${REPO_ROOT}/.oauth2-cookie-secret"
fi

RENDERED_VALUES="${REPO_ROOT}/k8s/20-kagent-values-rendered.yaml"
sed \
  -e "s|<keycloak-issuer-url>|${KEYCLOAK_ISSUER_URL}|g" \
  -e "s|<keycloak-client-secret>|${KEYCLOAK_CLIENT_SECRET}|g" \
  -e "s|<oauth2-cookie-secret>|${OAUTH2_COOKIE_SECRET}|g" \
  "${REPO_ROOT}/k8s/20-kagent-values.yaml" > "${RENDERED_VALUES}"

echo "=== Creating demo namespace and broken app ==="
kubectl apply -f "${REPO_ROOT}/k8s/00-namespace.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/10-broken-app.yaml"

echo "=== Creating kagent namespace and LLM secret ==="
kubectl create namespace kagent 2>/dev/null || true
kubectl delete secret kagent-openai -n kagent 2>/dev/null || true
kubectl create secret generic kagent-openai \
  --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY}" -n kagent

echo "=== Installing kagent CRDs and chart ==="
helm upgrade --install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace \
  --version 0.9.12
helm uninstall kagent -n kagent 2>/dev/null || true
sleep 5
helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --version 0.9.12 \
  -f "${RENDERED_VALUES}" \
  --timeout 15m \
  --wait=false

echo "=== Waiting for kagent core pods ==="
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=kagent -n kagent --timeout=600s 2>/dev/null || \
  kubectl get pods -n kagent

echo "=== Applying ModelConfig and agents ==="
kubectl apply -f "${REPO_ROOT}/k8s/30-modelconfig.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/31-observer-agent.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/35-remediator-agent.yaml"

echo "=== Installing observability ==="
kubectl apply -f "${REPO_ROOT}/k8s/50-otel-collector.yaml"

echo ""
echo "=== kagent setup complete ==="
echo ""
echo "Next:"
echo "  1. make ui            # http://localhost:8080"
echo "  2. make jaeger        # http://localhost:16686 (optional)"
echo "  3. make credentials"
echo "  4. make break"
echo "  5. Alice: observer-agent → remediator-agent"
echo "     Bob:   observer-agent → remediator-agent-intern"
if [[ -f "${REPO_ROOT}/.demo-users" ]]; then
  echo ""
  echo "Demo UI logins:"
  grep -E '^(ALICE_|BOB_|KAGENT_UI)' "${REPO_ROOT}/.demo-users" || true
fi
