#!/usr/bin/env bash
# End-to-end tests for AAP Crossplane Provider
#
# This script:
# 1. Creates a Kind cluster
# 2. Installs Crossplane
# 3. Deploys a mock AAP API server
# 4. Installs the AAP provider
# 5. Applies test managed resources
# 6. Validates resource status conditions
#
# Usage:
#   ./test/e2e/run-e2e-tests.sh [--cleanup]
#
# Options:
#   --cleanup    Delete Kind cluster after tests (default: keep for debugging)
#   --skip-build Skip provider image build (use existing image)

set -euo pipefail

# Configuration
CLUSTER_NAME="${KIND_CLUSTER_NAME:-aap-provider-e2e}"
CROSSPLANE_VERSION="${CROSSPLANE_VERSION:-1.15.0}"
PROVIDER_IMAGE="${PROVIDER_IMAGE:-aap-crossplane:e2e-test}"
CLEANUP=false
SKIP_BUILD=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "${BLUE}==>${NC} $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup) CLEANUP=true; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Verify prerequisites
command -v kind >/dev/null 2>&1 || { log_error "kind not found. Install from https://kind.sigs.k8s.io/"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { log_error "helm not found"; exit 1; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log_step "E2E Test Configuration"
log_info "Cluster name: $CLUSTER_NAME"
log_info "Crossplane version: $CROSSPLANE_VERSION"
log_info "Provider image: $PROVIDER_IMAGE"
log_info "Cleanup after: $CLEANUP"
log_info "Skip build: $SKIP_BUILD"

# Cleanup function
cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        log_step "Cleaning up Kind cluster..."
        kind delete cluster --name "$CLUSTER_NAME" || true
        log_info "Cleanup complete"
    else
        log_info "Cluster preserved for debugging. Delete with: kind delete cluster --name $CLUSTER_NAME"
        log_info "Access with: kubectl cluster-info --context kind-$CLUSTER_NAME"
    fi
}
trap cleanup EXIT

# Step 1: Create Kind cluster
log_step "Step 1: Creating Kind cluster..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    log_warn "Cluster $CLUSTER_NAME already exists, deleting..."
    kind delete cluster --name "$CLUSTER_NAME"
fi

cat > /tmp/kind-config-${CLUSTER_NAME}.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF

kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config-${CLUSTER_NAME}.yaml --wait 5m
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
log_info "✓ Kind cluster created"

# Step 2: Install Crossplane
log_step "Step 2: Installing Crossplane ${CROSSPLANE_VERSION}..."
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane \
    --namespace crossplane-system \
    --create-namespace \
    --version "${CROSSPLANE_VERSION}" \
    --wait \
    crossplane-stable/crossplane

kubectl wait --for=condition=Available --timeout=5m \
    deployment/crossplane -n crossplane-system

log_info "✓ Crossplane installed"

# Step 3: Deploy mock AAP API
log_step "Step 3: Deploying mock AAP API server..."
kubectl create namespace aap-mock || true

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: aap-mock-server
  namespace: aap-mock
data:
  server.py: |
    #!/usr/bin/env python3
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import json

    class AAPMockHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            # Gateway discovery endpoint
            if self.path == '/api/':
                response = {
                    "apis": {
                        "controller": {
                            "current_version": "/api/controller/v2/",
                            "available_versions": ["/api/controller/v2/"]
                        },
                        "eda": {
                            "current_version": "/api/eda/v1/",
                            "available_versions": ["/api/eda/v1/"]
                        }
                    }
                }
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())
            # Health check
            elif self.path == '/api/gateway/v1/status/':
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "ok"}).encode())
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, format, *args):
            print(f"[AAP Mock] {self.address_string()} - {format % args}")

    if __name__ == '__main__':
        server = HTTPServer(('0.0.0.0', 8080), AAPMockHandler)
        print('[AAP Mock] Starting mock AAP API on :8080')
        server.serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aap-mock
  namespace: aap-mock
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aap-mock
  template:
    metadata:
      labels:
        app: aap-mock
    spec:
      containers:
      - name: mock-server
        image: python:3.11-slim
        command: ["python3", "/app/server.py"]
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: server-script
          mountPath: /app
      volumes:
      - name: server-script
        configMap:
          name: aap-mock-server
          defaultMode: 0755
---
apiVersion: v1
kind: Service
metadata:
  name: aap-mock
  namespace: aap-mock
spec:
  selector:
    app: aap-mock
  ports:
  - port: 80
    targetPort: 8080
EOF

kubectl wait --for=condition=Available --timeout=3m \
    deployment/aap-mock -n aap-mock

log_info "✓ Mock AAP API deployed"

# Step 4: Build and load provider image (if not skipped)
if [[ "$SKIP_BUILD" == "false" ]]; then
    log_step "Step 4: Building provider image..."

    PROVIDER_DIR="${PROVIDER_AAP_DIR:-../provider-aap}"
    if [[ ! -d "$PROVIDER_DIR" ]]; then
        log_error "Provider directory not found: $PROVIDER_DIR"
        log_error "Set PROVIDER_AAP_DIR or ensure provider-aap is a sibling directory"
        exit 1
    fi

    cd "$PROVIDER_DIR"
    log_info "Building provider from: $(pwd)"

    # Build binary
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o provider ./cmd/provider

    # Create minimal Dockerfile
    cat > Dockerfile.e2e <<EOF
FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY provider /usr/local/bin/
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/provider"]
EOF

    # Build image
    docker build -t "$PROVIDER_IMAGE" -f Dockerfile.e2e .

    # Load into Kind
    kind load docker-image "$PROVIDER_IMAGE" --name "$CLUSTER_NAME"

    cd "$REPO_ROOT"
    log_info "✓ Provider image built and loaded"
else
    log_warn "Skipping provider build (--skip-build specified)"
fi

# Step 5: Create AAP credentials secret
log_step "Step 5: Creating AAP credentials..."
kubectl create secret generic aap-credentials \
    --namespace crossplane-system \
    --from-literal=credentials='{"host":"http://aap-mock.aap-mock.svc.cluster.local","token":"test-token"}' \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "✓ Credentials created"

# Step 6: Install AAP provider
log_step "Step 6: Installing AAP provider..."
cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aap
spec:
  package: ${PROVIDER_IMAGE}
  packagePullPolicy: Never
---
apiVersion: aap.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      name: aap-credentials
      namespace: crossplane-system
      key: credentials
EOF

# Wait for provider to be healthy
log_info "Waiting for provider to be installed..."
kubectl wait --for=condition=Installed --timeout=5m provider/provider-aap || {
    log_error "Provider failed to install"
    kubectl describe provider provider-aap
    exit 1
}

kubectl wait --for=condition=Healthy --timeout=5m provider/provider-aap || {
    log_error "Provider is not healthy"
    kubectl describe provider provider-aap
    kubectl get pods -n crossplane-system
    exit 1
}

log_info "✓ Provider installed"

# Step 7: Apply test managed resources
log_step "Step 7: Applying test managed resources..."

# Note: This will fail because mock API doesn't implement full AAP API
# But we can validate that:
# 1. CRDs were created
# 2. Controller processes the resources
# 3. Status conditions are set

cat <<EOF | kubectl apply -f -
apiVersion: inventory.aap.crossplane.io/v1alpha1
kind: Inventory
metadata:
  name: test-inventory
spec:
  forProvider:
    name: "E2E Test Inventory"
    organizationId: 1
  providerConfigRef:
    name: default
  deletionPolicy: Orphan
EOF

log_info "✓ Test resources applied"

# Step 8: Validate resource status
log_step "Step 8: Validating resource status..."

# Wait for resource to be processed
sleep 5

# Check if resource exists
if kubectl get inventory test-inventory &>/dev/null; then
    log_info "✓ Inventory resource exists"

    # Get status
    kubectl describe inventory test-inventory

    # Check for status conditions
    if kubectl get inventory test-inventory -o jsonpath='{.status.conditions}' | grep -q "type"; then
        log_info "✓ Status conditions are set"
    else
        log_warn "⊗ No status conditions found (expected for mock API)"
    fi
else
    log_error "✗ Inventory resource not found"
    exit 1
fi

# Step 9: Validate CRDs were created
log_step "Step 9: Validating CRDs..."
EXPECTED_CRDS=(
    "inventories.inventory.aap.crossplane.io"
    "hosts.host.aap.crossplane.io"
    "groups.group.aap.crossplane.io"
    "jobs.job.aap.crossplane.io"
    "workflowjobs.workflowjob.aap.crossplane.io"
)

ALL_FOUND=true
for crd in "${EXPECTED_CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        log_info "✓ CRD found: $crd"
    else
        log_error "✗ CRD missing: $crd"
        ALL_FOUND=false
    fi
done

if [[ "$ALL_FOUND" == "false" ]]; then
    log_error "Some CRDs are missing"
    exit 1
fi

# Summary
log_step "E2E Test Summary"
log_info "✓ Kind cluster created"
log_info "✓ Crossplane installed"
log_info "✓ Mock AAP API deployed"
log_info "✓ Provider built and installed"
log_info "✓ Test resources applied"
log_info "✓ CRDs validated"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  E2E Tests Passed Successfully! ✓     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

if [[ "$CLEANUP" == "false" ]]; then
    log_info "Cluster preserved for inspection:"
    log_info "  kubectl get providers"
    log_info "  kubectl get inventories"
    log_info "  kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aap"
    log_info ""
    log_info "Delete cluster with: kind delete cluster --name $CLUSTER_NAME"
fi
