# Documentation

This repo is organized into **building** the AAP Crossplane provider (image/package) and **deploying** it (Crossplane, credentials, provider install, and managed resources).

## Build (provider image and package)

Scripts and manifests for building the provider **controller image** and (optionally) the **package image** (xpkg) that Crossplane installs from.

| Doc | Description |
|-----|-------------|
| [build/BUILD-PROVIDER-IMAGE.md](build/BUILD-PROVIDER-IMAGE.md) | Build the controller image with Podman |
| [build/CROSSPLANE-PACKAGE-IMAGE.md](build/CROSSPLANE-PACKAGE-IMAGE.md) | Package image (xpkg) vs controller image; build and push xpkg |
| [build/PUSH-TO-QUAY-AND-OPENSHIFT.md](build/PUSH-TO-QUAY-AND-OPENSHIFT.md) | Push image to Quay and point OpenShift at it |

**Artifacts:** [build/](../build/) — `build-provider-image-podman.sh`, `build-provider-openshift.sh`, `provider-aap-buildconfig.yaml`, `provider-aap-buildconfig-external-registry.yaml`

## Deploy (Crossplane + provider on cluster)

Steps and manifests for installing Crossplane, creating AAP credentials, installing the provider, and applying managed resources.

| Doc | Description |
|-----|-------------|
| [deploy/openshift-deploy.md](deploy/openshift-deploy.md) | Full OpenShift deploy: Crossplane, provider, credentials, validation |
| [deploy/DEPLOY-AAP-PROVIDER-OPENSHIFT.md](deploy/DEPLOY-AAP-PROVIDER-OPENSHIFT.md) | Deploy via Quay (push image, then install on cluster) |
| [deploy/DEPLOY-ON-CRC.md](deploy/DEPLOY-ON-CRC.md) | Deploy on CRC / OpenShift Local (UID range, Quay) |
| [deploy/VALIDATE-AAP-PROVIDER-API.md](deploy/VALIDATE-AAP-PROVIDER-API.md) | Validate provider CRDs vs running AAP API |

**Artifacts:** [deploy/](../deploy/) — Crossplane subscription/Helm values, `provider.yaml`, credentials script, runtime config, testing jobs.

## Quick links

- **Build from scratch:** [BUILD.md](../BUILD.md) (scaffold, generate, compile provider binary)
- **Build image (Podman):** `./build/build-provider-image-podman.sh aap-crossplane:latest`
- **Deploy on OpenShift:** [deploy/openshift-deploy.md](deploy/openshift-deploy.md)
