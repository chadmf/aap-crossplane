# Multi-Architecture Build for AAP Crossplane Provider

This guide explains how to build the AAP Crossplane provider for multiple architectures (amd64 and arm64) with Terraform support included.

## Overview

The AAP Crossplane provider requires:
- Provider binary built for target architecture
- Terraform 1.5.7 (last MPL-licensed version)
- Terraform AAP provider 1.4.0
- Multi-arch container image supporting both linux/amd64 and linux/arm64

## Prerequisites

- Go 1.24+
- Docker with buildx OR Podman
- Access to container registry (Quay.io, Docker Hub, or private registry)
- Provider source code at `../provider-aap` (or set `PROVIDER_AAP_DIR`)

## Critical: Terraform Must Be Included

The build script at `build/build-provider-multi-arch.sh` only builds the Go binary without Terraform. To create a working provider image, you must use the proper build process that includes Terraform.

### Correct Build Process

The provider Dockerfile (in provider-aap repository) must include Terraform installation. The standard Upjet provider template includes this, but verify your Dockerfile contains:

```dockerfile
# Build stage
FROM --platform=$BUILDPLATFORM golang:1.24 as builder
ARG TARGETOS
ARG TARGETARCH

# Download and install Terraform
ARG TERRAFORM_VERSION=1.5.7
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip -o terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/ && \
    rm terraform.zip

# Download Terraform AAP provider
ARG TERRAFORM_PROVIDER_VERSION=1.4.0
ARG TERRAFORM_PROVIDER_SOURCE=ansible/aap
RUN mkdir -p /terraform/providers && \
    curl -fsSL https://github.com/ansible/terraform-provider-aap/releases/download/v${TERRAFORM_PROVIDER_VERSION}/terraform-provider-aap_${TERRAFORM_PROVIDER_VERSION}_linux_${TARGETARCH}.zip -o provider.zip && \
    unzip provider.zip -d /terraform/providers && \
    rm provider.zip

# Build provider binary
WORKDIR /workspace
COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -o provider ./cmd/provider

# Final stage
FROM gcr.io/distroless/static:nonroot
COPY --from=builder /usr/local/bin/terraform /usr/local/bin/
COPY --from=builder /terraform/providers /root/.terraform.d/plugins
COPY --from=builder /workspace/provider /usr/local/bin/
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/provider"]
```

## Build Methods

### Method 1: Using Provider Makefile (Recommended)

From the provider-aap repository:

```bash
cd ~/Documents/GitHub/provider-aap

# Build multi-arch with Docker buildx
docker buildx create --name multiarch-builder --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag quay.io/cferman/provider-aap:0.1.15-multiarch \
  --push \
  .

# Or with Podman
podman manifest create quay.io/cferman/provider-aap:0.1.15-multiarch
podman build --platform linux/amd64 \
  --tag quay.io/cferman/provider-aap:0.1.15-multiarch-amd64 .
podman build --platform linux/arm64 \
  --tag quay.io/cferman/provider-aap:0.1.15-multiarch-arm64 .
podman manifest add quay.io/cferman/provider-aap:0.1.15-multiarch \
  quay.io/cferman/provider-aap:0.1.15-multiarch-amd64
podman manifest add quay.io/cferman/provider-aap:0.1.15-multiarch \
  quay.io/cferman/provider-aap:0.1.15-multiarch-arm64
podman manifest push quay.io/cferman/provider-aap:0.1.15-multiarch
```

### Method 2: Using Build Helper Script

The `build/build-provider-multi-arch.sh` script builds only the binary. Use it if you have a custom Dockerfile:

```bash
# Set provider directory
export PROVIDER_AAP_DIR=~/Documents/GitHub/provider-aap

# Build and push multi-arch (requires proper Dockerfile with Terraform)
./build/build-provider-multi-arch.sh quay.io/cferman/provider-aap:0.1.15-multiarch --push

# Build locally (single arch - useful for testing)
./build/build-provider-multi-arch.sh quay.io/cferman/provider-aap:0.1.15-test
```

## Verify Multi-Arch Build

After pushing to registry:

```bash
# With Docker
docker buildx imagetools inspect quay.io/cferman/provider-aap:0.1.15-multiarch

# With Podman
podman manifest inspect quay.io/cferman/provider-aap:0.1.15-multiarch

# Expected output should show:
# - linux/amd64
# - linux/arm64
```

## Verify Terraform is Included

Pull and inspect the image to confirm Terraform is present:

```bash
# Pull for your architecture
podman pull quay.io/cferman/provider-aap:0.1.15-multiarch

# Run interactive shell (requires debug image or add shell in Dockerfile for testing)
# For distroless, you can check with manifest inspection or by running the container
podman run --rm quay.io/cferman/provider-aap:0.1.15-multiarch --version

# The provider should start without "terraform: command not found" errors
# Check logs when deployed to verify Terraform initialization
```

## Troubleshooting

### Issue: "Exec format error"

**Symptom**: Provider pod crashes with:
```
exec container process `/usr/local/bin/provider`: Exec format error
```

**Cause**: Architecture mismatch. Image was built for wrong architecture (e.g., arm64 binary on amd64 cluster).

**Solution**:
1. Verify cluster architecture:
   ```bash
   kubectl get nodes -o wide
   # Check ARCHITECTURE column
   ```

2. Rebuild for correct architecture or use multi-arch image:
   ```bash
   docker buildx build --platform linux/amd64,linux/arm64 --push ...
   ```

### Issue: "terraform: command not found"

**Symptom**: Provider logs show:
```
Error: failed to initialize Terraform: exec: "terraform": executable file not found
```

**Cause**: Terraform not included in container image.

**Solution**: Ensure Dockerfile includes Terraform installation (see "Correct Build Process" above). The `build-provider-multi-arch.sh` script only builds the binary.

### Issue: "terraform-provider-aap not found"

**Symptom**: Provider logs show:
```
Error: provider registry.terraform.io/ansible/aap could not be found
```

**Cause**: Terraform AAP provider not pre-installed in image.

**Solution**: Download and include Terraform AAP provider in Dockerfile:
```dockerfile
RUN curl -fsSL https://github.com/ansible/terraform-provider-aap/releases/download/v1.4.0/terraform-provider-aap_1.4.0_linux_${TARGETARCH}.zip -o provider.zip && \
    unzip provider.zip -d /terraform/providers
COPY --from=builder /terraform/providers /root/.terraform.d/plugins
```

### Issue: Cannot push to registry

**Symptom**:
```
Error: unauthorized: access to the requested resource is not authorized
```

**Solution**: Login to registry first:
```bash
# Quay.io
podman login quay.io
# or
docker login quay.io

# OpenShift internal registry
oc whoami -t | podman login -u $(oc whoami) --password-stdin \
  default-route-openshift-image-registry.apps.your-cluster.com
```

## Architecture Verification Checklist

Before deploying to production:

- [ ] Multi-arch manifest includes both linux/amd64 and linux/arm64
- [ ] Terraform 1.5.7 is included in image
- [ ] Terraform AAP provider 1.4.0 is included in image
- [ ] Image pushed to accessible registry
- [ ] Provider binary is correct version
- [ ] Tested on both amd64 and arm64 clusters (if applicable)

## CI/CD Integration

For automated builds in GitHub Actions:

```yaml
name: Build Multi-Arch Provider

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Login to Quay.io
        uses: docker/login-action@v3
        with:
          registry: quay.io
          username: ${{ secrets.QUAY_USERNAME }}
          password: ${{ secrets.QUAY_TOKEN }}
      
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            quay.io/cferman/provider-aap:${{ github.ref_name }}
            quay.io/cferman/provider-aap:latest
          build-args: |
            TERRAFORM_VERSION=1.5.7
            TERRAFORM_PROVIDER_VERSION=1.4.0
```

## Version History

- 0.1.15-multiarch: First multi-arch release with Terraform 1.5.7 and AAP provider 1.4.0
- Supports: linux/amd64, linux/arm64

## Next Steps

After building, see:
- [OpenShift Multi-Arch Deployment](../deploy/OPENSHIFT-MULTIARCH-DEPLOYMENT.md) - Deploy to OpenShift
- [BUILD.md](../../BUILD.md) - General build instructions
- [CROSSPLANE-PACKAGE-IMAGE.md](CROSSPLANE-PACKAGE-IMAGE.md) - Package as Crossplane package
