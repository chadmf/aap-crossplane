# Build and push the AAP Crossplane provider image (Podman)

This guide covers building the AAP Crossplane provider **controller** image with **Podman**, pushing it to a registry (**OpenShift internal**, **Quay**, or other), and pointing **OpenShift** at it.

Crossplane installs providers from a **package** image (xpkg) that references this controller image. If you see **"package.yaml not found in package"**, build and push the **package** image too — see [CROSSPLANE-PACKAGE-IMAGE.md](CROSSPLANE-PACKAGE-IMAGE.md).

## Prerequisites

- **Podman** installed. On macOS, start the Podman machine if needed: `podman machine init` then `podman machine start`.
- **Go** (to build the provider binary)
- **provider-aap** repo (the Upjet-based AAP provider). By default the script expects it as a sibling of aap-crossplane: `../provider-aap`. Override with `PROVIDER_AAP_DIR`.

**Apple Silicon (M1/M2):** If your cluster nodes are amd64 (typical for OpenShift), build for amd64: `GOARCH=amd64 ./build/build-provider-image-podman.sh ...`. Otherwise the provider pod can fail with **Exec format error**.

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

## Push the image

Crossplane needs a **fully qualified image name** (`registry/repository:tag`) that your cluster can pull.

### OpenShift integrated registry

If the cluster exposes the internal image registry:

```bash
# Get registry route (if it exists)
REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null)

podman login -u kubeadmin -p $(oc whoami -t) $REGISTRY --tls-verify=false
podman tag aap-crossplane:latest $REGISTRY/crossplane-system/aap-crossplane:latest
podman push $REGISTRY/crossplane-system/aap-crossplane:latest --tls-verify=false
```

Then [deploy/provider.yaml](../deploy/provider.yaml) can use: `image-registry.openshift-image-registry.svc:5000/crossplane-system/aap-crossplane:latest`.

### Quay.io

With the image already built locally (e.g. `aap-crossplane:latest`):

```bash
# Log in (use your Quay password or an encrypted robot token)
podman login quay.io -u <your-quay-username>

# Tag and push (replace <your-quay-username> with your Quay org or username)
podman tag aap-crossplane:latest quay.io/<your-quay-username>/aap-crossplane:latest
podman push quay.io/<your-quay-username>/aap-crossplane:latest
```

Create the repository **`aap-crossplane`** under your Quay account if it does not exist. Make it **public** so OpenShift can pull without image pull secrets, or add a pull secret to **`crossplane-system`** (see [deploy/provider.yaml](../deploy/provider.yaml) `packagePullSecrets`).

### Other registries

Tag and push the same way, e.g. Docker Hub or GHCR:

```bash
podman tag aap-crossplane:latest ghcr.io/<org>/aap-crossplane:latest
podman push ghcr.io/<org>/aap-crossplane:latest
```

On OpenShift you may need `imageContentSourcePolicy` or mirror config for private registries.

## Point OpenShift at the image

Set [deploy/provider.yaml](../deploy/provider.yaml) **`spec.package`** to your **package** (xpkg) image if you use Crossplane packages, or follow your install flow for the controller image reference. For a direct provider manifest using the controller image you built, use the image URL your cluster can reach (examples above).

Apply (or patch an existing provider):

```bash
kubectl apply -f deploy/provider.yaml

# Or patch the existing provider:
# kubectl patch provider aap-crossplane-provider --type=merge -p '{"spec":{"package":"quay.io/<your-quay-username>/aap-crossplane:latest"}}'
```

## Verify

Crossplane should pull the image and start the provider:

```bash
oc get provider.pkg.crossplane.io
oc get pods -n crossplane-system
```

Expect **`aap-crossplane-provider`** to show **INSTALLED=True** and **HEALTHY=True** once the image is pulled and the provider pod is running.

## Other Kubernetes clusters

Push to any registry the cluster can pull from, then set the provider **`spec.package`** (or equivalent) to that image reference. For local registries, configure node access or mirroring as needed.

## See also

- [CROSSPLANE-PACKAGE-IMAGE.md](CROSSPLANE-PACKAGE-IMAGE.md) – Package (xpkg) vs controller image; build and push the xpkg.
- [openshift-deploy.md](../deploy/openshift-deploy.md) – Full OpenShift deploy (Crossplane, credentials, provider).
- [deploy/provider.yaml](../deploy/provider.yaml) – Provider install manifest.
