# Deploy aap-crossplane on OpenShift

Steps to deploy Crossplane and the AAP Crossplane provider on **any OpenShift cluster** where Ansible Automation Platform (AAP) is already installed.

## Prerequisites

- **OpenShift cluster** with `kubectl`/`oc` access and your kubeconfig context set to the target cluster.
- **Helm 3.x** (or use the `helm` binary in the repo root after downloading once; see below).
- **AAP** already deployed on the cluster (e.g. via the Red Hat AAP Operator) in a namespace you know (e.g. `aap-operator` or `ansible-automation-platform`). You need the **in-cluster gateway URL** (AAP 2.5+ uses the gateway; do not use the controller service directly), e.g. `http://aap-gateway.<aap-namespace>.svc.cluster.local`, and admin credentials or an Application Token.

## 1. Install Crossplane

### Option A — Upbound Universal Crossplane (UXP) operator

Install **[Upbound Universal Crossplane](https://github.com/upbound/universal-crossplane)** via OperatorHub or CLI:

- Step-by-step: **[install-upbound-universal-crossplane.md](install-upbound-universal-crossplane.md)**  
- **`oc apply -f deploy/crossplane-operator-subscription.yaml`**  
- Uninstall / coexistence with Helm: [crossplane-uninstall-reinstall-operator.md](crossplane-uninstall-reinstall-operator.md).

### Option B — Helm (upstream chart)

Use the OpenShift-compatible values file so Crossplane pods run with UIDs in your cluster's restricted range. No SCC grants (e.g. `anyuid`) are required.

```bash
# From repo root
export HELM_HOME="$(pwd)/.helm"

# Create namespace (if not exists)
kubectl create namespace crossplane-system

# Add repo and install with OpenShift security context (no anyuid SCC needed)
./helm repo add crossplane-stable https://charts.crossplane.io/stable
./helm repo update
./helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  -f deploy/crossplane-values-openshift.yaml \
  --wait --timeout 5m
```

The values file [deploy/crossplane-values-openshift.yaml](../../deploy/crossplane-values-openshift.yaml) sets `runAsUser`/`runAsGroup` to `1000160000` (within the typical OpenShift namespace UID range) and pod-level `runAsNonRoot` and `seccompProfile` so the pods satisfy the **restricted** Security Context Constraint. If your cluster uses a different UID range, edit the values file and change `1000160000` to a value in your namespace's range (e.g. inspect an existing pod: `kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.securityContext.runAsUser}'`).

If you don't have Helm installed, you can download the binary into the repo (see [README.md](../../README.md)). If the install times out, check pods and continue to step 2.

## 2. Verify Crossplane

```bash
kubectl get pods -n crossplane-system
# Expect: crossplane-* and crossplane-rbac-manager-* Running
kubectl get crd | grep crossplane.io
```

## 3. Install the AAP Crossplane provider

The AAP provider is built from this repo's scaffold (see [BUILD.md](../../BUILD.md)). There is no pre-built image published.

1. **Apply provider CRDs** (from your built provider repo, e.g. provider-aap):

   ```bash
   kubectl apply -f /path/to/provider-aap/package/crds/
   ```

2. **Create AAP credentials Secret** in `crossplane-system` using an **AAP Application Token** (recommended). Use the **gateway** URL (AAP 2.5+: do not use the controller service; use the gateway so the provider talks to AAP via the gateway).
   - Create an Application Token in AAP: **Users** → your user → **Application Tokens** → Create (scope it to the organizations the provider will manage).
   - Create the secret (replace `<aap-namespace>`, `<gateway-service>`, and `<your-application-token>`):

   ```bash
   AAP_NS="<aap-namespace>"   # e.g. aap-operator
   AAP_HOST="http://<gateway-service>.${AAP_NS}.svc.cluster.local"   # e.g. aap-gateway.aap-operator.svc.cluster.local
   AAP_TOKEN="<your-application-token>"
   kubectl create secret generic aap-credentials -n crossplane-system \
     --from-literal=credentials="{\"host\":\"$AAP_HOST\",\"token\":\"$AAP_TOKEN\",\"insecure_skip_verify\":true}" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

   See [deploy/aap-credentials-secret.yaml](../../deploy/aap-credentials-secret.yaml) for details and username/password fallback. Or use `./deploy/create-aap-credentials-secret.sh` (optionally with credentials from `~/.docker/config.json`). Set **`AAP_HOST`** to the **gateway root** (e.g. `http://aap.<ns>.svc.cluster.local`) so **`GET {host}/api/`** succeeds; the embedded Terraform **ansible/aap** provider discovers **`current_version`** (the controller API base, i.e. **`/api/controller/v2/`** on AAP 2.5+). Do **not** append **`/api/controller`** to `host`.

3. **Apply ProviderConfig**: `kubectl apply -f provider/examples/providerconfig.yaml`

4. **Validate against the AAP API**: Use the combined suite [validate-aap-api-suite-job.yaml](../../deploy/testing-scripts/validate-aap-api-suite-job.yaml) — **internal ingress** + **`Host:`** (CRC), optional **`aap-credentials`** for full discovery. See [provider/AAP-HTTP-APIS.md](../../provider/AAP-HTTP-APIS.md). Then:

   ```bash
   kubectl apply -f deploy/testing-scripts/validate-aap-api-suite-job.yaml
   kubectl wait --for=condition=complete job/validate-aap-api-suite -n crossplane-system --timeout=300s
   kubectl logs job/validate-aap-api-suite -n crossplane-system
   ```

   Expect: `SUCCESS: AAP API is reachable from the cluster.`

5. **Run the provider** (choose one):
   - **Locally**: From the generated provider repo (provider-aap), run `make run` (connects to the cluster and reconciles using the in-cluster AAP API).
   - **In-cluster on OpenShift**: Build the image **on the cluster** so it lands in the internal registry: see [Build provider image on OpenShift](#build-provider-image-on-openshift) below.
   - **In-cluster (Podman)**: Build with [Podman](#build-provider-image-with-podman) then push to a registry (internal or external); set the image in [deploy/provider.yaml](../../deploy/provider.yaml) and `kubectl apply -f deploy/provider.yaml`.

6. **Apply managed resources**: e.g. `kubectl apply -f examples/example-inventory.yaml` (create an inventory), or `kubectl apply -f examples/example-job.yaml` (launch a job from an existing job template). Verify in the AAP UI. Note: the provider does not yet include a CRD to *create* job templates; see [examples/example-job-template.yaml](../../examples/example-job-template.yaml) for a reference shape if you extend the provider.

## Build provider image with Podman

If you don't have Docker but have **Podman**, use the script in this repo to build the AAP Crossplane provider image. It builds the Go binary for `linux/amd64` or `linux/arm64` (from your host arch) and runs `podman build` with the same Dockerfile and Terraform/AAP provider settings used by the generated provider (provider-aap).

**Prerequisites:** Podman, Go, and the [provider-aap](https://github.com/crossplane-contrib/provider-aap) repo (default: sibling of aap-crossplane, i.e. `../provider-aap`).

```bash
# From aap-crossplane repo root (default: provider-aap at ../provider-aap)
./build/build-provider-image-podman.sh aap-crossplane:latest

# Optional: custom provider-aap path
PROVIDER_AAP_DIR=/path/to/provider-aap ./build/build-provider-image-podman.sh aap-crossplane:v0.1.0
```

**Use the image on OpenShift:** Push to a registry your cluster can pull from (internal OpenShift registry or external such as Quay), then set [deploy/provider.yaml](../../deploy/provider.yaml) `spec.package` to that image (e.g. `image-registry.openshift-image-registry.svc:5000/crossplane-system/aap-crossplane:latest` or `quay.io/myorg/aap-crossplane:latest`) and apply:

```bash
kubectl apply -f deploy/provider.yaml
```

See [BUILD-PROVIDER-IMAGE.md](../build/BUILD-PROVIDER-IMAGE.md) for push options (internal registry vs external).

## Build provider image on OpenShift

Build the provider image **on your OpenShift cluster** so the image is stored in the internal image registry (no external push needed).

**OpenShift Local:** Many OpenShift Local installs do not include the legacy build subsystem (BuildConfig/ImageStream). If `./build/build-provider-openshift.sh` reports that the cluster doesn't have BuildConfig, use [Build provider image with Podman](#build-provider-image-with-podman) and push the image to an external registry (e.g. Quay), then set `spec.package` in [deploy/provider.yaml](../../deploy/provider.yaml) to that image.

**Prerequisites:** `oc` logged in to a cluster that has BuildConfig (e.g. full OpenShift), [provider-aap](https://github.com/crossplane-contrib/provider-aap) repo (default: `../provider-aap`), and the `crossplane-system` namespace (e.g. from step 1).

1. **Apply the BuildConfig and ImageStream** (one-time):

   ```bash
   kubectl apply -f build/provider-aap-buildconfig.yaml
   ```

2. **Run the build script** (builds the Go binary, uploads context, and runs the OpenShift build):

   ```bash
   ./build/build-provider-openshift.sh
   ```

   Optional: custom namespace or provider path:

   ```bash
   BUILD_NAMESPACE=crossplane-system PROVIDER_AAP_DIR=/path/to/provider-aap ./build/build-provider-openshift.sh
   ```

3. **Point the Provider at the internal image** and install:

   ```bash
   # Edit deploy/provider.yaml: set spec.package to:
   # image-registry.openshift-image-registry.svc:5000/crossplane-system/aap-crossplane:latest
   kubectl apply -f deploy/provider.yaml
   ```

The image is available at `image-registry.openshift-image-registry.svc:5000/crossplane-system/aap-crossplane:latest` for in-cluster pulls. The build uses `linux/amd64`; for arm64 nodes set `GOARCH=arm64` when running the script.

**Troubleshooting — `InvalidOutputReference: Output image could not be resolved`:** The cluster's **internal image registry** is not available (check `oc get svc -n openshift-image-registry`). Two options:

1. **Use an external registry for the build output** (recommended when internal registry is missing):
   - Create a push secret in `crossplane-system` for your registry (e.g. Quay, GHCR):  
     `oc create secret docker-registry provider-aap-push-secret -n crossplane-system --docker-server=<registry> --docker-username=<user> --docker-password=<token>`
   - Edit [build/provider-aap-buildconfig-external-registry.yaml](../../build/provider-aap-buildconfig-external-registry.yaml): set `output.to.name` to your image (e.g. `quay.io/myorg/aap-crossplane:latest`).
   - Apply it (replacing the default BuildConfig):  
     `kubectl apply -f build/provider-aap-buildconfig-external-registry.yaml`
   - Run `./build/build-provider-openshift.sh`; the image will be pushed to your registry. Set `spec.package` in [deploy/provider.yaml](../../deploy/provider.yaml) to that image.

2. **Build with Podman and push** to a registry the cluster can pull from, then set `spec.package` to that image (see [Build provider image with Podman](#build-provider-image-with-podman)).

## Quick reference

| Item | Value |
| --- | --- |
| Crossplane namespace | `crossplane-system` |
| AAP namespace | Your AAP install namespace (e.g. `aap-operator`) |
| In-cluster AAP URL (gateway) | `http://aap-gateway.<aap-namespace>.svc.cluster.local` |
| API path (AAP 2.5+) | `/api/controller/v2/` (use gateway; do not use controller service) |
| Gateway service name | From `kubectl get svc -n <aap-namespace>` (e.g. `aap-gateway`) |
