#!/usr/bin/env bash
set -euo pipefail

: "${LINODE_TOKEN:?LINODE_TOKEN must be set}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD must be set}"
: "${OPENAI_API_KEY:?OPENAI_API_KEY must be set}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${REPO_ROOT}/scripts/infra-up.sh"
"${REPO_ROOT}/scripts/kagent-up.sh"
