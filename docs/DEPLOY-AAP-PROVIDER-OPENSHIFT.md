# Push aap-crossplane to Quay and deploy on OpenShift

Use this flow when your OpenShift cluster does **not** expose an internal image registry (no route/service to push to). You push the image to Quay from your machine, then point the cluster at it.

## Prerequisites

- **OpenShift cluster** with `kubectl`/`oc` access; set your kubeconfig context to the target cluster.
- **Quay account** (or another registry your cluster can pull from).

## 1. Push images to Quay (from your machine)

Crossplane needs a **package** image (xpkg), not just the controller image. If you only push the controller image, the provider will fail with **"package.yaml not found in package"**. See [CROSSPLANE-PACKAGE-IMAGE.md](../deploy/CROSSPLANE-PACKAGE-IMAGE.md) for the full flow. Short version:

1. **Controller image** — build and push with a specific tag (e.g. `v0.1.0`) so the package can reference it:
   ```bash
   ./deploy/build-provider-image-podman.sh aap-crossplane:v0.1.0
   podman login quay.io -u <your-quay-username>
   podman tag aap-crossplane:v0.1.0 quay.io/<your-quay-username>/aap-crossplane:v0.1.0
   podman push quay.io/<your-quay-username>/aap-crossplane:v0.1.0
   ```
2. **Package image** — from the **provider-aap** repo, build the xpkg (embedding the controller image) and push as `:latest`:
   ```bash
   cd ../provider-aap
   crossplane xpkg build -f package --embed-runtime-image=quay.io/<your-quay-username>/aap-crossplane:v0.1.0 -o aap-crossplane.xpkg
   crossplane xpkg push quay.io/<your-quay-username>/aap-crossplane:latest -f aap-crossplane.xpkg
   ```

Create the repository `aap-crossplane` under your Quay account if it doesn’t exist. If the repo is **public**, Crossplane can pull the package image with no pull secret—skip step 3. Use step 3 only for **private** repos.

## 2. Apply provider CRDs on the cluster

From this repo, with the **provider-aap** repo at `../provider-aap` (or set `PROVIDER_AAP_DIR`):

```bash
# Ensure your kubeconfig context targets the OpenShift cluster
PROVIDER_AAP_DIR="${PROVIDER_AAP_DIR:-$(pwd)/../provider-aap}"
kubectl apply -f "${PROVIDER_AAP_DIR}/package/crds/"
```

## 3. Quay pull secret (private repos only)

**Public Quay repositories do not need a pull secret.** Apply [provider.yaml](../deploy/provider.yaml) with only `spec.package` set.

If the package image is **private**, create a registry secret and reference it on the Provider:

```bash
kubectl create secret docker-registry quay-pull-secret -n crossplane-system \
  --docker-server=quay.io \
  --docker-username=<your-quay-username> \
  --docker-password='<your-quay-password-or-robot-token>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then add to the Provider spec:

```yaml
spec:
  packagePullSecrets:
    - name: quay-pull-secret
```

## 4. AAP credentials secret

Create the secret with your AAP gateway URL and Application Token (see [aap-credentials-secret.yaml](../deploy/aap-credentials-secret.yaml)). Replace `<aap-namespace>` and `<your-application-token>`:

```bash
AAP_NS="<aap-namespace>"
AAP_HOST="http://aap-gateway.${AAP_NS}.svc.cluster.local"
AAP_TOKEN="<your-application-token>"
kubectl create secret generic aap-credentials -n crossplane-system \
  --from-literal=credentials="{\"host\":\"$AAP_HOST\",\"token\":\"$AAP_TOKEN\",\"insecure_skip_verify\":true}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 5. ProviderConfig and Provider

```bash
kubectl apply -f provider/examples/providerconfig.yaml
kubectl apply -f deploy/provider.yaml
```

Set [provider.yaml](../deploy/provider.yaml) `spec.package` to your package image (e.g. `quay.io/<your-quay-username>/aap-crossplane:latest`) before applying.

## 6. Verify

```bash
kubectl get provider.pkg.crossplane.io
kubectl get pods -n crossplane-system
```

Expect the provider `aap-crossplane-provider` **INSTALLED=True** and **HEALTHY=True**, and a running `aap-crossplane-provider-*` pod.

## Reference

- [CROSSPLANE-PACKAGE-IMAGE.md](../deploy/CROSSPLANE-PACKAGE-IMAGE.md) – why you need a package image (xpkg) and how to build/push it  
- [openshift-deploy.md](openshift-deploy.md) – full OpenShift deploy guide  
- [PUSH-TO-QUAY-AND-OPENSHIFT.md](PUSH-TO-QUAY-AND-OPENSHIFT.md) – Quay push and OpenShift  
- [provider.yaml](../deploy/provider.yaml) – set `spec.package` to your **package** image; `packagePullSecrets` only if the image is private
