#!/usr/bin/env bash
# Build AAP Crossplane provider for multiple architectures
#
# This script builds the provider binary for both amd64 and arm64 architectures,
# creates Docker images, and optionally pushes a multi-arch manifest.
#
# Usage:
#   ./build/build-provider-multi-arch.sh <image-tag> [--push]
#
# Example:
#   ./build/build-provider-multi-arch.sh quay.io/cferman/aap-crossplane:latest
#   ./build/build-provider-multi-arch.sh quay.io/cferman/aap-crossplane:v0.1.0 --push
#
# Environment variables:
#   PROVIDER_AAP_DIR - Path to provider-aap repository (default: ../provider-aap)
#   PLATFORMS - Comma-separated list of platforms (default: linux/amd64,linux/arm64)
#
# Docker without --push uses buildx --load, which supports only one platform; the script
# loads the first listed platform and still builds all binaries for podman manifest flow.

set -euo pipefail

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
IMAGE_TAG="${1:-}"
PUSH_IMAGE=false

if [[ -z "$IMAGE_TAG" ]]; then
    log_error "Usage: $0 <image-tag> [--push]"
    log_error "Example: $0 quay.io/cferman/aap-crossplane:latest"
    exit 1
fi

if [[ "${2:-}" == "--push" ]]; then
    PUSH_IMAGE=true
fi

# Configuration
PROVIDER_AAP_DIR="${PROVIDER_AAP_DIR:-../provider-aap}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log_step "Multi-arch Build Configuration"
log_info "Provider directory: $PROVIDER_AAP_DIR"
log_info "Image tag: $IMAGE_TAG"
log_info "Platforms: $PLATFORMS"
log_info "Push to registry: $PUSH_IMAGE"

# Verify provider directory exists
if [[ ! -d "$PROVIDER_AAP_DIR" ]]; then
    log_error "Provider directory not found: $PROVIDER_AAP_DIR"
    log_error "Set PROVIDER_AAP_DIR environment variable or ensure provider-aap is a sibling directory"
    exit 1
fi

cd "$PROVIDER_AAP_DIR"
log_info "Working directory: $(pwd)"

# Check if Docker or Podman is available
if command -v docker &>/dev/null; then
    CONTAINER_CMD="docker"
elif command -v podman &>/dev/null; then
    CONTAINER_CMD="podman"
else
    log_error "Neither docker nor podman found. Please install one of them."
    exit 1
fi

log_info "Using container command: $CONTAINER_CMD"

# Check if buildx is available (for docker multi-arch)
if [[ "$CONTAINER_CMD" == "docker" ]]; then
    if ! docker buildx version &>/dev/null; then
        log_warn "Docker buildx not available. Installing..."
        docker buildx install || {
            log_error "Failed to install docker buildx"
            log_error "Multi-arch builds require Docker buildx"
            log_error "See: https://docs.docker.com/buildx/working-with-buildx/"
            exit 1
        }
    fi

    # Create buildx builder if it doesn't exist
    if ! docker buildx inspect multiarch-builder &>/dev/null; then
        log_info "Creating buildx builder: multiarch-builder"
        docker buildx create --name multiarch-builder --use
    else
        docker buildx use multiarch-builder
    fi
fi

# Step 1: Build binaries for each architecture
log_step "Step 1: Building provider binaries"

IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"
for i in "${!PLATFORM_ARRAY[@]}"; do
    PLATFORM_ARRAY[$i]=$(echo "${PLATFORM_ARRAY[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
done
for platform in "${PLATFORM_ARRAY[@]}"; do
    os=$(echo "$platform" | cut -d/ -f1)
    arch=$(echo "$platform" | cut -d/ -f2)

    log_info "Building for $platform..."
    CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build -mod=mod -o "provider-$arch" ./cmd/provider

    if [[ -f "provider-$arch" ]]; then
        size=$(ls -lh "provider-$arch" | awk '{print $5}')
        log_info "✓ Built provider-$arch ($size)"
    else
        log_error "✗ Failed to build provider-$arch"
        exit 1
    fi
done

# Step 2: Create Dockerfile if it doesn't exist
log_step "Step 2: Preparing Dockerfile"

DOCKERFILE="Dockerfile.multiarch"
cat > "$DOCKERFILE" <<'EOF'
# Multi-arch Dockerfile for AAP Crossplane Provider
ARG TARGETARCH
FROM gcr.io/distroless/static:nonroot

# Re-declare ARG after FROM to make it available in this stage
ARG TARGETARCH

# Copy the appropriate binary for this architecture
COPY provider-${TARGETARCH} /usr/local/bin/provider

USER 65532:65532
ENTRYPOINT ["/usr/local/bin/provider"]
EOF

log_info "✓ Created $DOCKERFILE"

# Step 3: Build and optionally push multi-arch image
log_step "Step 3: Building multi-arch container image"

if [[ "$CONTAINER_CMD" == "docker" ]]; then
    # --load only supports a single platform; multi-arch local load is not supported by the docker driver.
    DOCKER_PLATFORMS="$PLATFORMS"
    if [[ "$PUSH_IMAGE" != "true" ]] && [[ "${#PLATFORM_ARRAY[@]}" -gt 1 ]]; then
        DOCKER_PLATFORMS="${PLATFORM_ARRAY[0]}"
        log_warn "Docker buildx cannot --load a multi-platform image. Loading locally for $DOCKER_PLATFORMS only (use --push for: $PLATFORMS)."
    fi

    # Use Docker buildx for multi-arch
    BUILD_ARGS=(
        "buildx"
        "build"
        "--platform" "$DOCKER_PLATFORMS"
        "-f" "$DOCKERFILE"
        "-t" "$IMAGE_TAG"
    )

    if [[ "$PUSH_IMAGE" == "true" ]]; then
        BUILD_ARGS+=("--push")
        log_info "Building and pushing multi-arch image..."
    else
        BUILD_ARGS+=("--load")
        log_info "Building image for local docker load (platform: $DOCKER_PLATFORMS)..."
    fi

    BUILD_ARGS+=(".")

    docker "${BUILD_ARGS[@]}"

elif [[ "$CONTAINER_CMD" == "podman" ]]; then
    # Use Podman manifest for multi-arch
    log_info "Creating Podman manifest..."

    # Remove existing manifest/image if it exists
    podman manifest rm "$IMAGE_TAG" 2>/dev/null || podman rmi "$IMAGE_TAG" 2>/dev/null || true

    # Create manifest
    podman manifest create "$IMAGE_TAG"

    # Build and add each architecture to manifest
    for platform in "${PLATFORM_ARRAY[@]}"; do
        arch=$(echo "$platform" | cut -d/ -f2)
        log_info "Building for $platform and adding to manifest..."

        podman build \
            --platform "$platform" \
            -f "$DOCKERFILE" \
            -t "${IMAGE_TAG}-${arch}" \
            --build-arg TARGETARCH="$arch" \
            .

        podman manifest add "$IMAGE_TAG" "${IMAGE_TAG}-${arch}"
    done

    if [[ "$PUSH_IMAGE" == "true" ]]; then
        log_info "Pushing multi-arch manifest..."
        podman manifest push "$IMAGE_TAG" "$IMAGE_TAG"
    fi
fi

# Step 4: Verify
log_step "Step 4: Verifying build"

if [[ "$CONTAINER_CMD" == "docker" ]]; then
    docker buildx imagetools inspect "$IMAGE_TAG" 2>/dev/null || log_warn "Could not inspect image (may not be pushed yet)"
elif [[ "$CONTAINER_CMD" == "podman" ]]; then
    podman manifest inspect "$IMAGE_TAG" | grep -A2 "platform" || log_warn "Could not inspect manifest"
fi

# Cleanup
log_step "Cleanup"
log_info "Removing temporary build artifacts..."
for platform in "${PLATFORM_ARRAY[@]}"; do
    arch=$(echo "$platform" | cut -d/ -f2)
    rm -f "provider-${arch}"
done
rm -f "$DOCKERFILE"

# Summary
log_step "Build Summary"
log_info "✓ Multi-arch provider built successfully"
log_info "  Image: $IMAGE_TAG"
log_info "  Platforms: $PLATFORMS"

if [[ "$PUSH_IMAGE" == "true" ]]; then
    log_info "  Status: Pushed to registry"
    log_info ""
    log_info "Deploy to OpenShift:"
    log_info "  oc patch provider aap-crossplane-provider --type=merge -p '{\"spec\":{\"package\":\"$IMAGE_TAG\"}}'"
else
    log_info "  Status: Built locally (use --push to push to registry)"
    log_info ""
    log_info "To push to registry:"
    log_info "  $0 $IMAGE_TAG --push"
fi

echo ""
log_info "${GREEN}Build complete!${NC}"
