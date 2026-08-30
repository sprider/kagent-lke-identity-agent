#!/usr/bin/env bash
set -euo pipefail

: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD must be set}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${HOME}/.kube/kagent-identity-config"
SECRET_FILE="${REPO_ROOT}/.keycloak-client-secret"
USERS_FILE="${REPO_ROOT}/.demo-users"

ALICE_PASSWORD="${ALICE_PASSWORD:-alice123}"
BOB_PASSWORD="${BOB_PASSWORD:-bob123}"

export KUBECONFIG="${KUBECONFIG_PATH}"

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

echo "Keycloak URL: ${KEYCLOAK_URL}"
KEYCLOAK_URL="${KEYCLOAK_URL%:80}"

echo "=== Waiting for Keycloak to be ready ==="
for i in {1..60}; do
  if curl -sf "${KEYCLOAK_URL}/realms/master" >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for Keycloak... ($i/60)"
  sleep 5
done

echo "=== Authenticating as Keycloak admin ==="
TOKEN_RESPONSE=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "username=admin" \
  --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=admin-cli")

TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')

echo "=== Creating realm kagent-demo ==="
curl -sf -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"realm":"kagent-demo","enabled":true,"sslRequired":"none","registrationAllowed":false,"loginWithEmailAllowed":true}' \
  || echo "Realm already exists or creation failed; continuing"

echo "=== Creating client kagent-ui ==="
curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/kagent-demo/clients" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId":"kagent-ui",
    "enabled":true,
    "redirectUris":["http://localhost:8080/*","http://localhost:8080/oauth2/callback"],
    "webOrigins":["+"],
    "publicClient":false,
    "standardFlowEnabled":true,
    "directAccessGrantsEnabled":true
  }' || echo "Client already exists or creation failed; continuing"

echo "=== Getting client UUID and secret ==="
CLIENT_UUID=$(curl -sf "${KEYCLOAK_URL}/admin/realms/kagent-demo/clients?clientId=kagent-ui" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id')

if [[ -z "${CLIENT_UUID}" || "${CLIENT_UUID}" == "null" ]]; then
  echo "ERROR: Could not find kagent-ui client"
  exit 1
fi

curl -sf -X PUT "${KEYCLOAK_URL}/admin/realms/kagent-demo/clients/${CLIENT_UUID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(curl -sf "${KEYCLOAK_URL}/admin/realms/kagent-demo/clients/${CLIENT_UUID}" \
        -H "Authorization: Bearer ${TOKEN}" | jq '.redirectUris = ["http://localhost:8080/*","http://localhost:8080/oauth2/callback"] | .webOrigins = ["+"]')" \
  || echo "WARN: could not update client redirect URIs; continuing"

CLIENT_SECRET=$(curl -sf "${KEYCLOAK_URL}/admin/realms/kagent-demo/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.value')

if [[ -z "${CLIENT_SECRET}" || "${CLIENT_SECRET}" == "null" ]]; then
  echo "ERROR: Could not retrieve client secret"
  exit 1
fi

printf '%s' "${CLIENT_SECRET}" > "${SECRET_FILE}"
chmod 600 "${SECRET_FILE}"

echo "=== Creating groups ==="
for group in platform-engineers interns; do
  curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/kagent-demo/groups" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${group}\"}" || echo "Group ${group} already exists or creation failed; continuing"
done

get_group_id() {
  local name=$1
  curl -sf "${KEYCLOAK_URL}/admin/realms/kagent-demo/groups?search=${name}&exact=true" \
    -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id'
}

GROUP_PE_ID=$(get_group_id "platform-engineers")
GROUP_IN_ID=$(get_group_id "interns")

get_user_id() {
  local email=$1
  curl -sf "${KEYCLOAK_URL}/admin/realms/kagent-demo/users?email=${email}&exact=true" \
    -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id'
}

set_user_password() {
  local user_id=$1
  local password=$2
  curl -sf -X PUT "${KEYCLOAK_URL}/admin/realms/kagent-demo/users/${user_id}/reset-password" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}"
}

ensure_user() {
  local username=$1
  local email=$2
  local first_name=$3
  local last_name=$4
  local group_id=$5
  local password=$6

  local user_id
  user_id=$(get_user_id "${email}")

  if [[ -z "${user_id}" || "${user_id}" == "null" ]]; then
    echo "Creating user ${email}"
    curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/kagent-demo/users" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"username\":\"${username}\",
        \"email\":\"${email}\",
        \"firstName\":\"${first_name}\",
        \"lastName\":\"${last_name}\",
        \"enabled\":true,
        \"emailVerified\":true
      }"
    user_id=$(get_user_id "${email}")
  else
    echo "User ${email} already exists - updating password and group"
  fi

  if [[ -z "${user_id}" || "${user_id}" == "null" ]]; then
    echo "ERROR: Could not resolve user id for ${email}"
    exit 1
  fi

  set_user_password "${user_id}" "${password}"

  if [[ -n "${group_id}" && "${group_id}" != "null" ]]; then
    curl -sf -X PUT "${KEYCLOAK_URL}/admin/realms/kagent-demo/users/${user_id}/groups/${group_id}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{}' || echo "Could not add ${email} to group; continuing"
  fi
}

echo "=== Creating demo users with UI login passwords ==="
ensure_user "alice" "alice@corp.com" "Alice" "Platform" "${GROUP_PE_ID}" "${ALICE_PASSWORD}"
ensure_user "bob" "bob@corp.com" "Bob" "Intern" "${GROUP_IN_ID}" "${BOB_PASSWORD}"

echo "=== Adding groups mapper to client ==="
curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/kagent-demo/clients/${CLIENT_UUID}/protocol-mappers/models" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name":"groups",
    "protocol":"openid-connect",
    "protocolMapper":"oidc-group-membership-mapper",
    "config":{
      "claim.name":"groups",
      "full.path":"false",
      "id.token.claim":"true",
      "access.token.claim":"true",
      "userinfo.token.claim":"true"
    }
  }' || echo "Mapper already exists or creation failed; continuing"

cat > "${USERS_FILE}" <<EOF
KEYCLOAK_URL=${KEYCLOAK_URL}
KEYCLOAK_REALM=kagent-demo
KAGENT_UI=http://localhost:8080
ALICE_USERNAME=alice
ALICE_EMAIL=alice@corp.com
ALICE_PASSWORD=${ALICE_PASSWORD}
BOB_USERNAME=bob
BOB_EMAIL=bob@corp.com
BOB_PASSWORD=${BOB_PASSWORD}
EOF
chmod 600 "${USERS_FILE}"

echo ""
echo "=== Keycloak configuration complete ==="
echo "Client secret written to: ${SECRET_FILE}"
echo "Demo user credentials:    ${USERS_FILE}"
echo "Keycloak issuer URL:      ${KEYCLOAK_URL}/realms/kagent-demo"
echo ""
echo "UI logins (after make ui):"
echo "  Alice: alice / ${ALICE_PASSWORD}"
echo "  Bob:   bob   / ${BOB_PASSWORD}"
