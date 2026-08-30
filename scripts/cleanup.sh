#!/usr/bin/env bash
set -euo pipefail

: "${LINODE_TOKEN:?LINODE_TOKEN must be set}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD must be set}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${HOME}/.kube/kagent-identity-config"

export TF_VAR_linode_token="${LINODE_TOKEN}"
export TF_VAR_keycloak_admin_password="${KEYCLOAK_ADMIN_PASSWORD}"

echo "=== Destroying LKE cluster ==="
cd "${REPO_ROOT}/terraform"
terraform destroy -auto-approve

echo "=== Removing local rendered files and secrets ==="
rm -f "${REPO_ROOT}/k8s/20-kagent-values-rendered.yaml"
rm -f "${REPO_ROOT}/.keycloak-client-secret"
rm -f "${REPO_ROOT}/.demo-users"
rm -f "${REPO_ROOT}/.oauth2-cookie-secret"
rm -f "${KUBECONFIG_PATH}"

echo "Cleanup complete."
