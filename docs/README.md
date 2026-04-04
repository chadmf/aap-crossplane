# Documentation

This repo is organized into **building** the AAP Crossplane provider (image/package) and **deploying** it (Crossplane, credentials, provider install, and managed resources).

## Quick Start

| Doc | Description |
|-----|-------------|
| [MULTIARCH-QUICK-REFERENCE.md](MULTIARCH-QUICK-REFERENCE.md) | 5-minute multi-arch deployment guide with troubleshooting |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Comprehensive troubleshooting guide for all common issues |

## Build (provider image and package)

Scripts and manifests for building the provider **controller image** and (optionally) the **package image** (xpkg) that Crossplane installs from.

| Doc | Description |
|-----|-------------|
| [build/MULTIARCH-BUILD.md](build/MULTIARCH-BUILD.md) | **Multi-architecture build** for amd64 and arm64 with Terraform |
| [build/BUILD-PROVIDER-IMAGE.md](build/BUILD-PROVIDER-IMAGE.md) | Build the controller image with Podman; push (OpenShift registry, Quay, other) and verify on cluster |
| [build/CROSSPLANE-PACKAGE-IMAGE.md](build/CROSSPLANE-PACKAGE-IMAGE.md) | Package image (xpkg) vs controller image; build and push xpkg |

**Artifacts:** [build/](../build/) — `build-provider-multi-arch.sh`, `build-provider-image-podman.sh`, `build-provider-openshift.sh`, `provider-aap-buildconfig.yaml`, `provider-aap-buildconfig-external-registry.yaml`

## Deploy (Crossplane + provider on cluster)

Steps and manifests for installing Crossplane, creating AAP credentials, installing the provider, and applying managed resources.

| Doc | Description |
|-----|-------------|
| [deploy/OPENSHIFT-MULTIARCH-DEPLOYMENT.md](deploy/OPENSHIFT-MULTIARCH-DEPLOYMENT.md) | **Complete multi-arch deployment** guide for OpenShift with internal AAP |
| [deploy/openshift-deploy.md](deploy/openshift-deploy.md) | Full OpenShift deploy: Crossplane, provider, credentials, validation |
| [deploy/DEPLOY-AAP-PROVIDER-OPENSHIFT.md](deploy/DEPLOY-AAP-PROVIDER-OPENSHIFT.md) | Deploy via Quay (push image, then install on cluster) |
| [deploy/DEPLOY-ON-CRC.md](deploy/DEPLOY-ON-CRC.md) | Deploy on CRC / OpenShift Local (UID range, Quay) |
| [deploy/VALIDATE-AAP-PROVIDER-API.md](deploy/VALIDATE-AAP-PROVIDER-API.md) | Validate provider CRDs vs running AAP API |

**Artifacts:** [deploy/](../deploy/) — Crossplane subscription/Helm values, `provider.yaml`, [deploy/providerconfig-default.yaml](../deploy/providerconfig-default.yaml) (default `ProviderConfig` for `aap-credentials`), credentials script, runtime config; API checks: [deploy/testing-scripts/validate-aap-api-suite-job.yaml](../deploy/testing-scripts/validate-aap-api-suite-job.yaml).

## Quick links

- **Quick Start (5 minutes):** [MULTIARCH-QUICK-REFERENCE.md](MULTIARCH-QUICK-REFERENCE.md)
- **Multi-arch build:** [build/MULTIARCH-BUILD.md](build/MULTIARCH-BUILD.md)
- **Multi-arch deployment:** [deploy/OPENSHIFT-MULTIARCH-DEPLOYMENT.md](deploy/OPENSHIFT-MULTIARCH-DEPLOYMENT.md)
- **Troubleshooting:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Build from scratch:** [BUILD.md](../BUILD.md) (scaffold, generate, compile provider binary)
- **Build image (Podman):** `./build/build-provider-image-podman.sh aap-crossplane:latest`
- **Build multi-arch:** `./build/build-provider-multi-arch.sh quay.io/yourorg/provider-aap:multiarch --push`
