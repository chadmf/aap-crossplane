# Build AAP Crossplane provider image with Podman

This document describes how to build the AAP Crossplane provider container image using **Podman** (no Docker required) so you can run the provider in-cluster (e.g. on OpenShift or CRC).

## Prerequisites

- **Podman** installed. On macOS, start the Podman machine if needed: `podman machine init` then `podman machine start`.
- **Go** (to build the provider binary)
- **provider-aap** repo (the Upjet-based AAP provider). By default the script expects it as a sibling of aap-crossplane: `../provider-aap`. Override with `PROVIDER_AAP_DIR`.

## Build

From the **aap-crossplane** repo root:

```bash
# Build image tagged provider-aap:latest (default)
./deploy/build-provider-image-podman.sh

# Custom tag
./deploy/build-provider-image-podman.sh provider-aap:v0.1.0

# Custom provider-aap path
PROVIDER_AAP_DIR=/path/to/provider-aap ./deploy/build-provider-image-podman.sh provider-aap:latest
```

The script:

1. Builds the provider Go binary for `linux/amd64` or `linux/arm64` (from your host).
2. Copies the Dockerfile, `terraformrc.hcl`, and binary from provider-aap into a temp build context.
3. Runs `podman build` with Terraform 1.5.7 and the Ansible AAP Terraform provider (e.g. 1.4.0), matching provider-aap’s `Makefile.aap`.

## Use the image

### CodeReady Containers (CRC)

Load the image into CRC so the cluster can run the provider:

```bash
podman save provider-aap:latest | crc image load -
```

Then set [provider.yaml](provider.yaml) to use that image and apply:

```yaml
spec:
  package: provider-aap:latest
```

```bash
kubectl apply -f deploy/provider.yaml
```

### Other OpenShift/Kubernetes clusters

- **Push to a registry** your cluster can pull from (e.g. Quay, GHCR, internal registry), then set `spec.package` in [provider.yaml](provider.yaml) to that image (e.g. `quay.io/myorg/provider-aap:v0.1.0`).
- Or use a local registry and configure the cluster to pull from it (e.g. `imageContentSourcePolicy` on OpenShift).

## See also

- [openshift-deploy.md](openshift-deploy.md) – Full OpenShift deploy flow, including Crossplane and AAP credentials.
- [provider.yaml](provider.yaml) – Provider install manifest; set `spec.package` to your built image.
