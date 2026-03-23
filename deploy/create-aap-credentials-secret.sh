#!/usr/bin/env bash
# Create the aap-credentials Secret in crossplane-system for the AAP Crossplane provider.
#
# 1. Create an Application Token in AAP (you must do this once):
#    AAP UI → Users → your user → Details → Application Tokens → Create.
#    Or: Settings → Users → select user → Application Tokens.
#    Scope the token to the organizations the provider will manage (e.g. Default).
#    Copy the token value (it is shown only once).
#
# 2. Set AAP_HOST and either AAP_TOKEN or add AAP to .docker/config.json, then run:
#    # Gateway root only — no /api/controller (provider discovers that via GET {host}/api/)
#    export AAP_HOST="http://aap-gateway.<aap-namespace>.svc.cluster.local"
#    # Or if your cluster has no aap-gateway Service, use the gateway entry Service (often `aap`):
#    # export AAP_HOST="http://aap.<aap-namespace>.svc.cluster.local"
#    export AAP_TOKEN="<paste-your-application-token>"   # optional if using config.json
#    ./deploy/create-aap-credentials-secret.sh
#
#    Token from config.json: ensure an entry exists in ~/.docker/config.json (or
#    DOCKER_CONFIG/config.json) for the AAP host. Key = AAP_AUTH_JSON_KEY if set,
#    else the host part of AAP_HOST. Value "auth" = base64(":" + token) or
#    base64(username:token); script uses the part after ":" as the token.
#    Requires jq when using config.json.
#
# AAP 2.5+: use a gateway *entry* Service (aap-gateway, or often `aap` / `aap-api` when aap-gateway is absent).
# Do not use the deprecated controller Service (aap-controller-service).
# From outside the cluster use your route URL without a path suffix, e.g. https://aap.example.com
#
set -euo pipefail

NAMESPACE="${CROSSPLANE_NAMESPACE:-crossplane-system}"
INSECURE="${AAP_INSECURE_SKIP_VERIFY:-true}"
AUTH_JSON="${DOCKER_CONFIG:-$HOME/.docker}/config.json"

# If AAP_TOKEN is not set, try to read token from .docker/config.json
if [[ -z "${AAP_TOKEN:-}" ]]; then
  if [[ -z "${AAP_HOST:-}" ]]; then
    echo "Usage: Set AAP_HOST and AAP_TOKEN (or add AAP entry to .docker/config.json), then run $0"
    echo ""
    echo "  export AAP_HOST=\"http://aap-gateway.aap-operator.svc.cluster.local\""
    echo "  # or: http://aap.aap-operator.svc.cluster.local  (if no aap-gateway Service)"
    echo "  export AAP_TOKEN=\"<your-application-token-from-aap-ui>\"   # or use config.json"
    echo "  $0"
    echo ""
    echo "Token from config.json: add an entry to ${AUTH_JSON} for your AAP host; key = host from AAP_HOST or set AAP_AUTH_JSON_KEY."
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    echo "AAP_TOKEN is not set; reading from config.json requires jq."
    echo "Install jq or set AAP_TOKEN."
    exit 1
  fi
  if [[ ! -f "$AUTH_JSON" ]]; then
    echo "AAP_TOKEN is not set and ${AUTH_JSON} not found."
    echo "Set AAP_TOKEN or create config.json with an 'auth' entry for your AAP host."
    exit 1
  fi
  # Resolve key: AAP_AUTH_JSON_KEY, or host part of AAP_HOST (no protocol/path)
  if [[ -n "${AAP_AUTH_JSON_KEY:-}" ]]; then
    AUTH_KEY="$AAP_AUTH_JSON_KEY"
  else
    AUTH_KEY=$(echo "$AAP_HOST" | sed -E 's#^https?://##; s#/.*##; s/:[0-9]+$//')
  fi
  # Try host key, then host+path, then full URL variants
  AUTH_B64=$(jq -r --arg k "$AUTH_KEY" --arg url "$AAP_HOST" '
    .auths[$k] // .auths[$url] // .auths["\($k)/api/controller"] // .auths["https://\($k)"] // .auths["http://\($k)"] |
    .auth // empty
  ' "$AUTH_JSON" 2>/dev/null || true)
  if [[ -z "$AUTH_B64" || "$AUTH_B64" == "null" ]]; then
    echo "No auth entry for key \"$AUTH_KEY\" (or variants) in ${AUTH_JSON}."
    echo "Set AAP_TOKEN or add an entry to config.json. Keys in file:"
    jq -r '.auths | keys[]' "$AUTH_JSON" 2>/dev/null || true
    exit 1
  fi
  AUTH_RAW=$(echo "$AUTH_B64" | base64 -d 2>/dev/null || base64 -D 2>/dev/null || true)
  if [[ "$AUTH_RAW" == *:* ]]; then
    AAP_TOKEN="${AUTH_RAW#*:}"
  else
    AAP_TOKEN="$AUTH_RAW"
  fi
  if [[ -z "${AAP_TOKEN:-}" ]]; then
    echo "Decoded auth for \"$AUTH_KEY\" is empty."
    exit 1
  fi
fi

if [[ -z "${AAP_HOST:-}" ]]; then
  echo "Usage: Set AAP_HOST (and optionally AAP_TOKEN or use .docker/config.json), then run $0"
  echo ""
  echo "  export AAP_HOST=\"http://aap-gateway.aap-operator.svc.cluster.local\""
  echo "  # or http://aap.aap-operator.svc.cluster.local"
  echo "  $0"
  exit 1
fi

CREDENTIALS=$(printf '%s' "{\"host\":\"${AAP_HOST}\",\"token\":\"${AAP_TOKEN}\",\"insecure_skip_verify\":${INSECURE}}")
kubectl create secret generic aap-credentials -n "$NAMESPACE" \
  --from-literal=credentials="$CREDENTIALS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret aap-credentials applied in namespace $NAMESPACE."
echo "Ensure a ProviderConfig (e.g. default) references this secret; then apply Inventory/Host resources."
