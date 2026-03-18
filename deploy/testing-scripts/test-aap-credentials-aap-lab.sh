#!/usr/bin/env bash
# Test aap-credentials against the AAP instance reachable from THIS cluster.
#
# For aap-lab (CRC/local OpenShift with AAP):
#   1. kubectl config use-context <your aap-lab context>   # e.g. aap-operator/localhost:6443
#   2. Ensure aap-credentials in crossplane-system uses THIS cluster's gateway, e.g.:
#        host: http://aap-gateway.aap-operator.svc.cluster.local/api/controller
#      (adjust namespace if AAP is not in aap-operator: oc get svc -A | grep aap-gateway)
#   3. Token must be an Application Token from THAT AAP (Users → Application Tokens).
#   4. Run: ./deploy/test-aap-credentials-aap-lab.sh
#
set -euo pipefail
NS="${CROSSPLANE_NAMESPACE:-crossplane-system}"
JOB=validate-aap-provider-api

CTX=$(kubectl config current-context 2>/dev/null || true)
echo "kubectl context: ${CTX:-unknown}"
echo "Namespace: $NS"
if ! kubectl get secret aap-credentials -n "$NS" &>/dev/null; then
  echo "ERROR: secret aap-credentials not found in $NS"
  exit 1
fi
echo "Found secret aap-credentials."

kubectl delete job "$JOB" -n "$NS" --ignore-not-found
kubectl apply -f "$(dirname "$0")/validate-aap-provider-api-alignment.yaml"
echo "Waiting for job (up to 90s)..."
if kubectl wait --for=condition=complete "job/$JOB" -n "$NS" --timeout=90s; then
  echo "=== Job logs ==="
  kubectl logs "job/$JOB" -n "$NS"
  echo "=== OK: credentials validated against AAP at host in secret ==="
else
  echo "=== Job failed or timed out — logs ==="
  kubectl logs "job/$JOB" -n "$NS" 2>/dev/null || kubectl describe "job/$JOB" -n "$NS"
  exit 1
fi
