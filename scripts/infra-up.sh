#!/usr/bin/env bash
set -euo pipefail

: "${LINODE_TOKEN:?LINODE_TOKEN must be set}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD must be set}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${HOME}/.kube/kagent-identity-config"

export TF_VAR_linode_token="${LINODE_TOKEN}"
export TF_VAR_keycloak_admin_password="${KEYCLOAK_ADMIN_PASSWORD}"

echo "=== Provisioning LKE cluster and Keycloak ==="
cd "${REPO_ROOT}/terraform"
terraform init
terraform apply -target=linode_lke_cluster.demo -auto-approve

echo "=== Writing kubeconfig ==="
mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
terraform output -raw kubeconfig > "${KUBECONFIG_PATH}"
chmod 600 "${KUBECONFIG_PATH}"

export KUBECONFIG="${KUBECONFIG_PATH}"
export KUBE_CONFIG_PATH="${KUBECONFIG_PATH}"

echo "=== Waiting for cluster API and Ready nodes ==="
for i in $(seq 1 90); do
  if kubectl get nodes --no-headers 2>/dev/null | grep -q .; then
    break
  fi
  echo "  waiting for nodes to join... (${i}/90)"
  sleep 10
done
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl get nodes

echo "=== Applying Helm and Kubernetes resources ==="
terraform apply -auto-approve

echo ""
echo "=== Infrastructure deployed ==="
KEYCLOAK_URL="$(terraform output -raw keycloak_url 2>/dev/null || echo 'not ready yet')"
KEYCLOAK_ADMIN_URL="$(terraform output -raw keycloak_admin_console_url 2>/dev/null || echo 'not ready yet')"
echo "Keycloak URL:        ${KEYCLOAK_URL}"
echo "Keycloak Admin URL:  ${KEYCLOAK_ADMIN_URL}"
echo "Admin credentials:   admin / ${KEYCLOAK_ADMIN_PASSWORD}"
echo ""
echo "Next: make kagent-up will configure Keycloak and install kagent automatically."
