# Deploy aap-crossplane on CRC (OpenShift Local)

This guide is for **CodeReady Containers (CRC)** / **OpenShift Local**: a single-node OpenShift cluster on your laptop. It covers Crossplane, the AAP Crossplane provider package image, OpenShift SCC (UID range), and reaching AAP from CRC.

## CRC vs full OpenShift

| Topic | On CRC |
|-------|--------|
| **BuildConfig** | Often **not** available. Use [Podman + Quay](DEPLOY-AAP-PROVIDER-OPENSHIFT.md) (or another registry) for provider images; do not rely on `build-provider-openshift.sh` unless your CRC has build APIs. |
| **Internal registry** | May be available; many users still push to **Quay** so the cluster can pull without extra registry setup. |
| **Node arch** | CRC VM is usually **linux/amd64**. Build the controller image for **amd64** (`GOARCH=amd64` on Apple Silicon). Build the **xpkg** on **amd64** too (see [CROSSPLANE-PACKAGE-IMAGE.md](../deploy/CROSSPLANE-PACKAGE-IMAGE.md) § Apple Silicon). |
| **Namespace UID range** | **Different per cluster.** You must align Helm values and `DeploymentRuntimeConfig` with `crossplane-system`’s range (steps below). |

## Prerequisites

- **CRC** installed and running: `crc start`
- **oc** configured for CRC: `eval $(crc oc-env)` then `oc login -u kubeadmin` (password from `crc console --credentials` or `crc status`)
- **Helm 3**
- **AAP reachable from CRC** — e.g. AAP on the same CRC cluster (operator + instance), or on another cluster/network with a URL the CRC pod network can reach (Route, NodePort, or host gateway). The provider uses the **gateway** URL (AAP 2.5+), e.g. `http://aap-gateway.<aap-namespace>.svc.cluster.local` when AAP runs on CRC.

## 1. Create namespace and read UID range

```bash
eval $(crc oc-env)
oc new-project crossplane-system 2>/dev/null || oc project crossplane-system

# Example output: 1000680000/10000  → use runAsUser/runAsGroup 1000680000
oc get namespace crossplane-system -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
```

Note the **first number** (e.g. `1000680000`). You will use it as `runAsUser` and `runAsGroup` in the next two files.

## 2. Edit Crossplane Helm values

Copy [deploy/crossplane-values-openshift.yaml](../deploy/crossplane-values-openshift.yaml) and set **every** `runAsUser` / `runAsGroup` (Crossplane and RBAC manager) to your namespace’s first UID from step 1.

## 3. Install Crossplane

From the **aap-crossplane** repo root (adjust path to your edited values file):

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  -f deploy/crossplane-values-openshift.yaml \
  --wait --timeout 10m

oc get pods -n crossplane-system
# Expect: crossplane-* and crossplane-rbac-manager-* Running
```

## 4. DeploymentRuntimeConfig (provider pods)

Provider pods also need UIDs in the same range. Edit [deploy/deployment-runtime-config-openshift.yaml](../deploy/deployment-runtime-config-openshift.yaml): set `runAsUser` / `runAsGroup` to the **same** value as in step 1, then:

```bash
oc apply -f deploy/deployment-runtime-config-openshift.yaml
```

## 5. Provider images (Quay recommended on CRC)

Crossplane installs a **package** image (xpkg), not the raw controller image. Full flow:

1. **Controller** (amd64): `GOARCH=amd64 ./deploy/build-provider-image-podman.sh aap-crossplane:v0.1.0` → push to `quay.io/<you>/aap-crossplane:v0.1.0`
2. **Package**: from **provider-aap**, `crossplane xpkg build` + `crossplane xpkg push` → `quay.io/<you>/aap-crossplane:latest`

See [CROSSPLANE-PACKAGE-IMAGE.md](../deploy/CROSSPLANE-PACKAGE-IMAGE.md) and [DEPLOY-AAP-PROVIDER-OPENSHIFT.md](DEPLOY-AAP-PROVIDER-OPENSHIFT.md). Use **Docker login** (or `~/.docker/config.json`) for `crossplane xpkg push` if you see Quay `UNAUTHORIZED`.

## 6. Install the provider on CRC

```bash
PROVIDER_AAP_DIR="${PROVIDER_AAP_DIR:-$(pwd)/../provider-aap}"
oc apply -f "${PROVIDER_AAP_DIR}/package/crds/"
```

Create **aap-credentials** and **ProviderConfig** (see [openshift-deploy.md](openshift-deploy.md) and [deploy/aap-credentials-secret.yaml](../deploy/aap-credentials-secret.yaml)).

Edit [deploy/provider.yaml](../deploy/provider.yaml): set `spec.package` to your package image (e.g. `quay.io/<you>/aap-crossplane:latest`). Add `packagePullSecrets` only if the image is private.

```bash
oc apply -f deploy/provider.yaml
```

If the provider deployment was created before you fixed UIDs or images, recreate it:

```bash
oc delete deployment -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider
```

Verify:

```bash
oc get provider.pkg.crossplane.io
oc get pods -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider
```

Expect **INSTALLED=True**, **HEALTHY=True**, and a running provider pod.

### Provider INSTALLED but HEALTHY=False

If status says the deployment has **no minimum availability**, check events:

```bash
oc get events -n crossplane-system --field-selector involvedObject.kind=ReplicaSet --sort-by='.lastTimestamp' | tail -15
```

**SCC / UID range:** If you see `runAsUser: Invalid value: 2000: must be in the ranges: [1000…]`, Crossplane’s `DeploymentRuntimeConfig` named **`default`** is empty or wrong. Apply [deploy/deployment-runtime-config-openshift.yaml](../deploy/deployment-runtime-config-openshift.yaml) with `runAsUser`/`runAsGroup` set to the **first number** from your namespace UID range (step 1), then wait for the provider deployment to roll out (or delete the provider deployment so it is recreated).

## 7. AAP not on CRC

If AAP runs **outside** CRC (e.g. on another OpenShift or on your LAN), set `AAP_HOST` in the credentials secret to a URL reachable **from inside CRC pods** (not `localhost`). Examples: a Route hostname, or your host’s IP and a forwarded port.

## See also

- [openshift-deploy.md](openshift-deploy.md) — full OpenShift flow (CRDs, validation job, managed resources)
- [docs/BUILD-PROVIDER-IMAGE.md](BUILD-PROVIDER-IMAGE.md) — build controller image with Podman
- [README.md](../README.md) — repo overview and build pipeline
