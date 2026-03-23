# Deploy aap-crossplane on CRC (OpenShift Local)

This guide is for **CodeReady Containers (CRC)** / **OpenShift Local**: a single-node OpenShift cluster on your laptop. It covers Crossplane, the AAP Crossplane provider package image, OpenShift SCC (UID range), and reaching AAP from CRC.

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

Copy [deploy/crossplane-values-openshift.yaml](../../deploy/crossplane-values-openshift.yaml) and set **every** `runAsUser` / `runAsGroup` (Crossplane and RBAC manager) to your namespace's first UID from step 1.

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

Provider pods also need UIDs in the same range. Edit [deploy/deployment-runtime-config-openshift.yaml](../../deploy/deployment-runtime-config-openshift.yaml): set `runAsUser` / `runAsGroup` to the **same** value as in step 1, then:

```bash
oc apply -f deploy/deployment-runtime-config-openshift.yaml
```

## 5. Provider images (Quay recommended on CRC)

Crossplane installs a **package** image (xpkg), not the raw controller image. Full flow:

1. **Controller** (amd64): `GOARCH=amd64 ./build/build-provider-image-podman.sh aap-crossplane:v0.1.0` → push to `quay.io/<you>/aap-crossplane:v0.1.0`
2. **Package**: from **provider-aap**, `crossplane xpkg build` + `crossplane xpkg push` → `quay.io/<you>/aap-crossplane:latest`

See [CROSSPLANE-PACKAGE-IMAGE.md](../build/CROSSPLANE-PACKAGE-IMAGE.md) and [DEPLOY-AAP-PROVIDER-OPENSHIFT.md](DEPLOY-AAP-PROVIDER-OPENSHIFT.md). Use **Docker login** (or `~/.docker/config.json`) for `crossplane xpkg push` if you see Quay `UNAUTHORIZED`.

## 6. Install the provider on CRC

```bash
PROVIDER_AAP_DIR="${PROVIDER_AAP_DIR:-$(pwd)/../provider-aap}"
oc apply -f "${PROVIDER_AAP_DIR}/package/crds/"
```

Create **aap-credentials** and **ProviderConfig** (see [openshift-deploy.md](openshift-deploy.md) and [deploy/aap-credentials-secret.yaml](../../deploy/aap-credentials-secret.yaml)).

Edit [deploy/provider.yaml](../../deploy/provider.yaml): set `spec.package` to your package image (e.g. `quay.io/<you>/aap-crossplane:latest`). Add `packagePullSecrets` only if the image is private.

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

**SCC / UID range:** If you see `runAsUser: Invalid value: 2000: must be in the ranges: [1000…]`, Crossplane's `DeploymentRuntimeConfig` named **`default`** is empty or wrong. Apply [deploy/deployment-runtime-config-openshift.yaml](../../deploy/deployment-runtime-config-openshift.yaml) with `runAsUser`/`runAsGroup` set to the **first number** from your namespace UID range (step 1), then wait for the provider deployment to roll out (or delete the provider deployment so it is recreated).

## 7. Validate the deployment on CRC

Run these after Crossplane and (optionally) the AAP provider are installed. Use `eval $(crc oc-env)` if `oc` is not already pointed at CRC.

### Crossplane core

```bash
oc get pods -n crossplane-system
# Expect: crossplane-* and crossplane-rbac-manager-* Running (2/2 or 1/1)

oc get crd | grep -E 'crossplane\.io|pkg\.crossplane\.io' | head -20

helm list -n crossplane-system
# Expect: crossplane deployed
```

### AAP provider package (if installed)

```bash
oc get provider.pkg.crossplane.io -o wide
# Expect: INSTALLED=True, HEALTHY=True

oc describe provider.pkg.crossplane.io aap-crossplane-provider | tail -30
# Check Conditions and Events for unpack/pull/runtime errors

oc get pods -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider
# Expect: Running, READY 1/1
```

### ProviderConfig and credentials

```bash
oc get providerconfig
oc describe providerconfig default
# Expect: healthy / ready (no invalid secret reference)

oc get secret aap-credentials -n crossplane-system
# Expect: exists if you use the default ProviderConfig
```

Confirm `aap-credentials` **`host`** is the **gateway root** (no `/api/controller` suffix): the embedded Terraform provider calls **`GET {host}/api/`** and uses **`current_version`** as the controller API base (same as **`/api/controller/v2/`** on AAP 2.5+). See [create-aap-credentials-secret.sh](../../deploy/create-aap-credentials-secret.sh).

### AAP API validation suite (optional Job)

One Job covers **ingress / Route checks** (CRC) and **authenticated** discovery (when `aap-credentials` is mounted):

- **Phase 1:** Internal ingress **`router-internal-default.openshift-ingress.svc.cluster.local`** + **`Host:`** (default **`aap-aap-operator.apps.127.0.0.1.nip.io`**) — unauthenticated GET **`/api/controller/v2/`** and **`/api/gateway/v1/status/`**. *Why:* nip.io hostnames resolve to **127.0.0.1** inside Pods; **`Host:`** fixes that. Set **`AAP_SKIP_INGRESS_CHECKS=1`** on the Job to skip phase 1.
- **Phase 2:** If Secret **`aap-credentials`** exists, mounts it (**optional** volume) and runs Terraform-equivalent **`GET {host}/api/`** discovery, controller resource paths, gateway v1, **`apis.eda`**.

For **`aap-credentials`**, use gateway **Service** DNS as **`host`** with **no path** (e.g. **`http://aap.aap-operator.svc.cluster.local`**). See [VALIDATE-AAP-PROVIDER-API.md](VALIDATE-AAP-PROVIDER-API.md) and [provider/AAP-HTTP-APIS.md](../../provider/AAP-HTTP-APIS.md).

```bash
oc delete job validate-aap-api-suite -n crossplane-system --ignore-not-found
oc apply -f deploy/testing-scripts/validate-aap-api-suite-job.yaml
oc wait --for=condition=complete job/validate-aap-api-suite -n crossplane-system --timeout=300s
oc logs job/validate-aap-api-suite -n crossplane-system
```

Expect **`SUITE COMPLETE.`** Phase 1 expects HTTP 200/302/401 (controller) and 200/302/401/403 (gateway v1). `curl` uses **`-k`** for dev TLS.

### End-to-end managed resource (optional)

```bash
oc apply -f examples/example-inventory.yaml
oc describe inventory example-inventory
# Expect Ready/Synced when AAP accepts the create
```

## See also

- [openshift-deploy.md](openshift-deploy.md) — full OpenShift flow (CRDs, validation job, managed resources)
- [BUILD-PROVIDER-IMAGE.md](../build/BUILD-PROVIDER-IMAGE.md) — build controller image with Podman
- [README.md](../../README.md) — repo overview and build pipeline
