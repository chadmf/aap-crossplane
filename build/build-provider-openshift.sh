#!/usr/bin/env bash
# Build the AAP Crossplane provider container image on local OpenShift.
# Prepares the build context (Go binary + Dockerfile + terraformrc.hcl), then
# triggers an OpenShift build; the image is pushed to the internal registry.
#
# Prerequisites:
#   - oc logged in to your OpenShift cluster
#   - BuildConfig applied: kubectl apply -f build/provider-aap-buildconfig.yaml
#   - provider-aap repo (default: ../provider-aap; set PROVIDER_AAP_DIR)
#
# Usage:
#   ./build/build-provider-openshift.sh
#   BUILD_NAMESPACE=crossplane-system PROVIDER_AAP_DIR=/path/to/provider-aap ./build/build-provider-openshift.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AAP_CROSSPLANE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVIDER_AAP_DIR="${PROVIDER_AAP_DIR:-$(dirname "$AAP_CROSSPLANE_ROOT")/provider-aap}"
BUILD_NAMESPACE="${BUILD_NAMESPACE:-crossplane-system}"

# OpenShift nodes are typically linux/amd64
GOARCH="${GOARCH:-amd64}"
PLATFORM="linux_${GOARCH}"

if [[ ! -d "$PROVIDER_AAP_DIR" ]]; then
  echo "ERROR: provider-aap dir not found at $PROVIDER_AAP_DIR"
  echo "Set PROVIDER_AAP_DIR to the path of your provider-aap repo."
  exit 1
fi

if ! command -v oc &>/dev/null; then
  echo "ERROR: oc not found. Log in to OpenShift and ensure oc is on PATH."
  exit 1
fi
out=$(oc get buildconfigs -A 2>&1) || true
if echo "$out" | grep -q "doesn't have a resource type"; then
  echo "ERROR: This cluster does not have OpenShift build APIs (BuildConfig)."
  echo "  OpenShift Local often does not include the legacy build subsystem."
  echo "  Recommended: ./build/build-provider-image-podman.sh aap-crossplane:latest"
  echo "  Then push to Quay (or another registry) and set spec.package in deploy/provider.yaml"
  exit 1
fi

IMG_DIR="$PROVIDER_AAP_DIR/cluster/images/provider-aap"
if [[ ! -f "$IMG_DIR/Dockerfile" ]] || [[ ! -f "$IMG_DIR/terraformrc.hcl" ]]; then
  echo "ERROR: $IMG_DIR/Dockerfile or terraformrc.hcl not found"
  exit 1
fi

echo "Building AAP Crossplane provider image on OpenShift..."
echo "  PROVIDER_AAP_DIR=$PROVIDER_AAP_DIR"
echo "  BUILD_NAMESPACE=$BUILD_NAMESPACE"
echo "  PLATFORM=$PLATFORM"

# Build the provider binary for linux (OpenShift node arch)
OUTPUT_BIN="$PROVIDER_AAP_DIR/_output/bin/$PLATFORM/provider"
mkdir -p "$(dirname "$OUTPUT_BIN")"
echo "  Building Go binary for $PLATFORM..."
(cd "$PROVIDER_AAP_DIR" && GOOS=linux GOARCH=$GOARCH go build -o "$OUTPUT_BIN" ./cmd/provider) || exit 1

# Prepare build context (same layout as Dockerfile expects)
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
cp "$IMG_DIR/Dockerfile" "$BUILD_DIR/"
cp "$IMG_DIR/terraformrc.hcl" "$BUILD_DIR/"
mkdir -p "$BUILD_DIR/bin/$PLATFORM"
cp "$PROVIDER_AAP_DIR/_output/bin/$PLATFORM/provider" "$BUILD_DIR/bin/$PLATFORM/"

# Ensure BuildConfig exists
if ! oc get buildconfig provider-aap -n "$BUILD_NAMESPACE" &>/dev/null; then
  echo "Applying BuildConfig and ImageStream..."
  oc apply -f "$SCRIPT_DIR/provider-aap-buildconfig.yaml"
fi

echo "  Starting OpenShift build (binary upload + Docker build)..."
oc start-build provider-aap --from-dir="$BUILD_DIR" -n "$BUILD_NAMESPACE" --follow

echo "Done. Image is in the internal registry:"
echo "  image-registry.openshift-image-registry.svc:5000/${BUILD_NAMESPACE}/aap-crossplane:latest"
echo ""
echo "Use it in deploy/provider.yaml:"
echo "  spec.package: image-registry.openshift-image-registry.svc:5000/${BUILD_NAMESPACE}/aap-crossplane:latest"
echo "Then: kubectl apply -f deploy/provider.yaml"
