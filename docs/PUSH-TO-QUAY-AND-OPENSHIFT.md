# Push aap-crossplane to Quay and use on OpenShift

## 1. Log in to Quay and push the image

From your machine (with the image already built as `aap-crossplane:latest`):

```bash
# Log in to Quay (use your Quay password or an encrypted robot token)
podman login quay.io -u <your-quay-username>

# Tag and push (replace <your-quay-username> with your Quay org or username)
podman tag aap-crossplane:latest quay.io/<your-quay-username>/aap-crossplane:latest
podman push quay.io/<your-quay-username>/aap-crossplane:latest
```

**Note:** Create the repository `aap-crossplane` under your Quay account (`quay.io/<your-quay-username>/aap-crossplane`) if it doesn’t exist. Make the repository **public** so OpenShift can pull without image pull secrets, or add a pull secret to the `crossplane-system` namespace (see [provider.yaml](provider.yaml) `packagePullSecrets`).

## 2. Point OpenShift at the Quay image

Set [provider.yaml](provider.yaml) `spec.package` to your image (e.g. `quay.io/<your-quay-username>/aap-crossplane:latest`), then apply:

```bash
# Ensure your kubeconfig context targets the OpenShift cluster
kubectl apply -f deploy/provider.yaml
# Or patch the existing provider:
# kubectl patch provider aap-crossplane-provider --type=merge -p '{"spec":{"package":"quay.io/<your-quay-username>/aap-crossplane:latest"}}'
```

## 3. Verify

Crossplane will pull the image from Quay and start the provider pod:

```bash
oc get provider.pkg.crossplane.io
oc get pods -n crossplane-system
```

Expect the provider `aap-crossplane-provider` to show **INSTALLED=True** and **HEALTHY=True** once the image is pulled and the provider pod is running.
