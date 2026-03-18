#!/usr/bin/env bash
# Build the AAP Crossplane provider container image using Podman.
# Run from aap-crossplane repo root; set PROVIDER_AAP_DIR if provider-aap is elsewhere.
#
# Usage:
#   ./deploy/build-provider-image-podman.sh [image-tag]
#   PROVIDER_AAP_DIR=/path/to/provider-aap ./deploy/build-provider-image-podman.sh aap-crossplane:v0.1.0
#
# Then push to a registry (e.g. Quay or OpenShift internal registry) and set spec.package in deploy/provider.yaml
# Or push to a registry and set deploy/provider.yaml spec.package to that image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AAP_CROSSPLANE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVIDER_AAP_DIR="${PROVIDER_AAP_DIR:-$(dirname "$AAP_CROSSPLANE_ROOT")/provider-aap}"
IMAGE_TAG="${1:-aap-crossplane:latest}"

if [[ ! -d "$PROVIDER_AAP_DIR" ]]; then
  echo "ERROR: provider-aap dir not found at $PROVIDER_AAP_DIR"
  echo "Set PROVIDER_AAP_DIR to the path of your provider-aap repo."
  exit 1
fi

# Detect arch for Go and Docker (linux_arm64 or linux_amd64).
# Override with GOARCH=amd64 when building on arm64 (e.g. M1) for an amd64 cluster.
ARCH=$(uname -m)
if [[ -z "${GOARCH:-}" ]]; then
  case "$ARCH" in
    x86_64|amd64)  GOARCH=amd64; ;;
    arm64|aarch64) GOARCH=arm64;  ;;
    *) echo "ERROR: unsupported arch $ARCH"; exit 1; ;;
  esac
fi
PLATFORM="linux_${GOARCH}"

# AAP Terraform provider vars (must match provider-aap Makefile.aap)
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.5.7}"
TERRAFORM_PROVIDER_SOURCE="${TERRAFORM_PROVIDER_SOURCE:-ansible/aap}"
TERRAFORM_PROVIDER_VERSION="${TERRAFORM_PROVIDER_VERSION:-1.4.0}"
TERRAFORM_PROVIDER_DOWNLOAD_NAME="${TERRAFORM_PROVIDER_DOWNLOAD_NAME:-terraform-provider-aap}"
TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX="${TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX:-https://github.com/ansible/terraform-provider-aap/releases/download/v${TERRAFORM_PROVIDER_VERSION}}"
TERRAFORM_NATIVE_PROVIDER_BINARY="${TERRAFORM_NATIVE_PROVIDER_BINARY:-terraform-provider-aap_v${TERRAFORM_PROVIDER_VERSION}}"

if ! command -v podman &>/dev/null; then
  echo "ERROR: podman not found. Install Podman; on macOS run 'podman machine start' if using Podman Desktop."
  exit 1
fi

echo "Building AAP Crossplane provider image with Podman..."
echo "  PROVIDER_AAP_DIR=$PROVIDER_AAP_DIR"
echo "  PLATFORM=$PLATFORM"
echo "  IMAGE_TAG=$IMAGE_TAG"

# Build the provider binary for linux
OUTPUT_BIN="$PROVIDER_AAP_DIR/_output/bin/$PLATFORM/provider"
mkdir -p "$(dirname "$OUTPUT_BIN")"
echo "  Building Go binary for $PLATFORM..."
(cd "$PROVIDER_AAP_DIR" && GOOS=linux GOARCH=$GOARCH go build -o "$OUTPUT_BIN" ./cmd/provider) || exit 1

# Build context: Dockerfile, terraformrc.hcl, and bin/
IMG_DIR="$PROVIDER_AAP_DIR/cluster/images/provider-aap"
if [[ ! -f "$IMG_DIR/Dockerfile" ]] || [[ ! -f "$IMG_DIR/terraformrc.hcl" ]]; then
  echo "ERROR: $IMG_DIR/Dockerfile or terraformrc.hcl not found"
  exit 1
fi

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
cp "$IMG_DIR/Dockerfile" "$BUILD_DIR/"
cp "$IMG_DIR/terraformrc.hcl" "$BUILD_DIR/"
mkdir -p "$BUILD_DIR/bin/$PLATFORM"
cp "$PROVIDER_AAP_DIR/_output/bin/$PLATFORM/provider" "$BUILD_DIR/bin/$PLATFORM/"

# Podman build (use --build-arg for all Dockerfile ARGs; TARGETOS/TARGETARCH for the binary path)
podman build \
  --platform "linux/$GOARCH" \
  --build-arg "TARGETOS=linux" \
  --build-arg "TARGETARCH=$GOARCH" \
  --build-arg "TERRAFORM_VERSION=$TERRAFORM_VERSION" \
  --build-arg "TERRAFORM_PROVIDER_SOURCE=$TERRAFORM_PROVIDER_SOURCE" \
  --build-arg "TERRAFORM_PROVIDER_VERSION=$TERRAFORM_PROVIDER_VERSION" \
  --build-arg "TERRAFORM_PROVIDER_DOWNLOAD_NAME=$TERRAFORM_PROVIDER_DOWNLOAD_NAME" \
  --build-arg "TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX=$TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX" \
  --build-arg "TERRAFORM_NATIVE_PROVIDER_BINARY=$TERRAFORM_NATIVE_PROVIDER_BINARY" \
  -t "$IMAGE_TAG" \
  "$BUILD_DIR"

echo "Done. Image: $IMAGE_TAG"
echo "  Push to a registry and set spec.package in deploy/provider.yaml"
echo "  Then set deploy/provider.yaml spec.package to this image and: kubectl apply -f deploy/provider.yaml"
