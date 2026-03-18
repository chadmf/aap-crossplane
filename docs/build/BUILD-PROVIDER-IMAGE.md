# Build AAP Crossplane provider image with Podman

This document describes how to build the AAP Crossplane provider **controller** image using **Podman** (no Docker required). Crossplane installs providers from a **package** image (xpkg) that references this controller image. If you see **"package.yaml not found in package"**, you need to build and push the package image too — see [CROSSPLANE-PACKAGE-IMAGE.md](CROSSPLANE-PACKAGE-IMAGE.md).

## Prerequisites

- **Podman** installed. On macOS, start the Podman machine if needed: `podman machine init` then `podman machine start`.
- **Go** (to build the provider binary)
- **provider-aap** repo (the Upjet-based AAP provider). By default the script expects it as a sibling of aap-crossplane: `../provider-aap`. Override with `PROVIDER_AAP_DIR`.

**Apple Silicon (M1/M2):** If your cluster nodes are amd64 (typical for OpenShift), build for amd64: `GOARCH=amd64 ./build/build-provider-image-podman.sh ...`. Otherwise the provider pod will fail with "Exec format error".

## Build

From the **aap-crossplane** repo root:

```bash
# Build image tagged aap-crossplane:latest (default)
./build/build-provider-image-podman.sh

# Custom tag
./build/build-provider-image-podman.sh aap-crossplane:v0.1.0

# Custom provider-aap path
PROVIDER_AAP_DIR=/path/to/provider-aap ./build/build-provider-image-podman.sh aap-crossplane:latest
```

The script:

1. Builds the provider Go binary for `linux/amd64` or `linux/arm64` (from your host).
2. Copies the Dockerfile, `terraformrc.hcl`, and binary from provider-aap into a temp build context.
3. Runs `podman build` with Terraform 1.5.7 and the Ansible AAP Terraform provider (e.g. 1.4.0), matching provider-aap's `Makefile.aap`.

## Use the image

### OpenShift

Crossplane requires a **fully qualified image name** (registry/repository:tag). Use one of these approaches:

**Option A – Push to the internal OpenShift registry** (if your cluster exposes the image registry):

```bash
# Get registry route (if it exists)
REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null)

podman login -u kubeadmin -p $(oc whoami -t) $REGISTRY --tls-verify=false
podman tag aap-crossplane:latest $REGISTRY/crossplane-system/aap-crossplane:latest
podman push $REGISTRY/crossplane-system/aap-crossplane:latest --tls-verify=false
```

Then [deploy/provider.yaml](../deploy/provider.yaml) should use: `image-registry.openshift-image-registry.svc:5000/crossplane-system/aap-crossplane:latest`.

**Option B – Push to an external registry** (Quay, Docker Hub, GHCR):

```bash
podman tag aap-crossplane:latest quay.io/<your-org>/aap-crossplane:latest
podman push quay.io/<your-org>/aap-crossplane:latest
```

Edit [deploy/provider.yaml](../deploy/provider.yaml) and set `spec.package` to that image (e.g. `quay.io/<your-org>/aap-crossplane:latest`), then:

```bash
kubectl apply -f deploy/provider.yaml
```

### Other OpenShift/Kubernetes clusters

- **Push to a registry** your cluster can pull from (e.g. Quay, GHCR, internal registry), then set `spec.package` in [deploy/provider.yaml](../deploy/provider.yaml) to that image (e.g. `quay.io/myorg/aap-crossplane:v0.1.0`).
- Or use a local registry and configure the cluster to pull from it (e.g. `imageContentSourcePolicy` on OpenShift).

## See also

- [CROSSPLANE-PACKAGE-IMAGE.md](CROSSPLANE-PACKAGE-IMAGE.md) – Why Crossplane needs a **package** image (xpkg), not just the controller image; how to build and push the xpkg.
- [openshift-deploy.md](../deploy/openshift-deploy.md) – Full OpenShift deploy flow, including Crossplane and AAP credentials.
- [deploy/provider.yaml](../deploy/provider.yaml) – Provider install manifest; set `spec.package` to the **package** image (see CROSSPLANE-PACKAGE-IMAGE.md).
