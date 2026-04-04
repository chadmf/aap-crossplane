# OpenShift Multi-Architecture Deployment Guide

Complete guide for deploying the AAP Crossplane provider multi-arch image to OpenShift, including configuration for internal AAP instances.

## Prerequisites

- OpenShift 4.12+ cluster with admin access
- Crossplane 2.2.0+ installed (or will install)
- AAP 2.5+ running in cluster (or external AAP instance)
- Multi-arch provider image: `quay.io/cferman/provider-aap:0.1.15-multiarch`
- `oc` CLI configured with cluster access
- `kubectl` or `oc` for Kubernetes operations

## Architecture Support

This deployment supports:
- linux/amd64 (x86_64)
- linux/arm64 (ARM 64-bit)

The multi-arch image automatically selects the correct architecture for your cluster nodes.

## Step 1: Verify Cluster Architecture

```bash
# Check node architecture
oc get nodes -o wide

# Expected output shows ARCHITECTURE column:
# NAME            STATUS   ROLES    AGE   VERSION   ARCHITECTURE
# master-0        Ready    master   45d   v1.34.4   amd64
# worker-1        Ready    worker   45d   v1.34.4   amd64
```

Most OpenShift clusters use amd64. ARM-based clusters will show arm64.

## Step 2: Install Crossplane

If Crossplane is not yet installed:

```bash
# Create namespace
oc create namespace crossplane-system

# Add Crossplane Helm repository
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Install Crossplane with OpenShift-compatible values
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --version 2.2.0 \
  -f deploy/crossplane-values-openshift.yaml \
  --wait --timeout 5m

# Verify installation
oc get pods -n crossplane-system

# Expected:
# NAME                                       READY   STATUS    RESTARTS   AGE
# crossplane-8468b98b68-5zr56                1/1     Running   0          2m
# crossplane-rbac-manager-d8b6b7ddc-rgpqz    1/1     Running   0          2m
```

The `deploy/crossplane-values-openshift.yaml` file contains OpenShift-specific security context settings:

```yaml
securityContextCrossplane:
  runAsUser: null
  runAsGroup: null
  allowPrivilegeEscalation: false

securityContextRBACManager:
  runAsUser: null
  runAsGroup: null
  allowPrivilegeEscalation: false
```

## Step 3: Deploy AAP Provider

### Option A: Using Pre-built Multi-Arch Image (Recommended)

```bash
# Create provider manifest
cat <<EOF | oc apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: aap-crossplane-provider
spec:
  package: quay.io/cferman/provider-aap:0.1.15-multiarch
  revisionActivationPolicy: Automatic
EOF

# Wait for provider to be installed
oc wait provider aap-crossplane-provider \
  --for=condition=Installed=True \
  --timeout=5m

# Verify provider status
oc get provider aap-crossplane-provider

# Expected:
# NAME                      INSTALLED   HEALTHY   PACKAGE
# aap-crossplane-provider   True        True      quay.io/cferman/provider-aap:0.1.15-multiarch
```

### Option B: Using Custom Image

If you built your own multi-arch image:

```bash
# Tag and push to accessible registry
IMAGE_TAG="quay.io/yourorg/provider-aap:custom-multiarch"
podman manifest push $IMAGE_TAG

# Deploy provider
oc apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: aap-crossplane-provider
spec:
  package: $IMAGE_TAG
  revisionActivationPolicy: Automatic
EOF
```

## Step 4: Verify Provider Deployment

```bash
# Check provider pod
oc get pods -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider

# Expected:
# NAME                                              READY   STATUS    RESTARTS   AGE
# aap-crossplane-provider-<hash>-<hash>             1/1     Running   0          2m

# Check provider logs (should show Terraform initialization)
oc logs -n crossplane-system deployment/<provider-deployment-name> --tail=50

# Successful logs show:
# - "Starting provider"
# - "Terraform initialized"
# - No "Exec format error" or "terraform: command not found"
```

### Troubleshooting Pod Issues

If pod is in CrashLoopBackOff:

```bash
# Get pod logs
POD=$(oc get pods -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider -o name)
oc logs $POD

# Common issues:

# 1. "Exec format error" - Architecture mismatch
#    Solution: Verify multi-arch manifest includes your cluster architecture
#    podman manifest inspect quay.io/cferman/provider-aap:0.1.15-multiarch

# 2. "terraform: command not found" - Missing Terraform in image
#    Solution: Rebuild image with Terraform included (see MULTIARCH-BUILD.md)

# 3. Image pull error - Registry authentication
#    Solution: Create image pull secret (see step 5)
```

## Step 5: Configure AAP Credentials

### Determine AAP Service URL

For in-cluster AAP deployment:

```bash
# List AAP services
oc get svc -n ansible-automation-platform

# Common service names:
# - aap (AAP 2.5+ gateway entry point - RECOMMENDED)
# - aap-gateway (alternative gateway service)
# - aap-api (alternative gateway service)

# Construct internal service URL
AAP_NAMESPACE="ansible-automation-platform"
AAP_SERVICE="aap"  # or aap-gateway
AAP_HOST="http://${AAP_SERVICE}.${AAP_NAMESPACE}.svc.cluster.local"

# Example:
# AAP_HOST="http://aap.ansible-automation-platform.svc.cluster.local"
```

For external AAP:

```bash
# Use external route (without /api/controller path)
AAP_HOST="https://aap.example.com"
```

### Create Application Token in AAP

1. Login to AAP UI
2. Navigate to: **Users** → your user → **Details** → **Application Tokens**
3. Click **Create**
4. Name: `crossplane-provider`
5. Scope: Select organizations the provider will manage
6. Copy the token (shown only once)

### Create Credentials Secret

```bash
# Set token from environment or prompt
export AAP_TOKEN="your-application-token-here"

# Or read from $AAP_CROSSPLANE environment variable
export AAP_TOKEN="${AAP_CROSSPLANE}"

# Create secret using helper script
export AAP_HOST="http://aap.ansible-automation-platform.svc.cluster.local"
./deploy/create-aap-credentials-secret.sh

# Or create manually
oc create secret generic aap-credentials \
  -n crossplane-system \
  --from-literal=credentials="{\"host\":\"${AAP_HOST}\",\"token\":\"${AAP_TOKEN}\",\"insecure_skip_verify\":true}"
```

### Understanding `insecure_skip_verify`

- For internal cluster services (http://): Set to `true` (no TLS)
- For external HTTPS with valid certs: Set to `false`
- For external HTTPS with self-signed certs: Set to `true`

### Apply ProviderConfig

```bash
# Apply default ProviderConfig
oc apply -f deploy/providerconfig-default.yaml

# Verify
oc get providerconfig

# Expected:
# NAME      AGE
# default   10s

# Check provider is now Healthy
oc get provider aap-crossplane-provider

# Expected:
# NAME                      INSTALLED   HEALTHY   PACKAGE
# aap-crossplane-provider   True        True      quay.io/cferman/provider-aap:0.1.15-multiarch
```

## Step 6: Test with Example Inventory

```bash
# Create test inventory
oc apply -f examples/example-inventory.yaml

# Watch reconciliation
oc get inventory -w

# Expected status progression:
# NAME                 READY   SYNCED   EXTERNAL-NAME   AGE
# example-inventory    False   False                    5s
# example-inventory    True    True     123             30s

# Get details
oc describe inventory example-inventory

# Verify in AAP UI
# Navigate to: Resources → Inventories
# Look for: "crossplane-example-inventory"
```

## Step 7: Advanced Configuration

### Using Private Registry

If provider image is in private registry:

```bash
# Create pull secret
oc create secret docker-registry quay-pull-secret \
  -n crossplane-system \
  --docker-server=quay.io \
  --docker-username=youruser \
  --docker-password=yourtoken

# Update Provider to use pull secret
oc patch provider aap-crossplane-provider --type=merge -p '
spec:
  packagePullSecrets:
    - name: quay-pull-secret
'
```

### Custom DeploymentRuntimeConfig

For advanced pod configuration (resources, node selectors, tolerations):

```bash
# Apply runtime config
oc apply -f deploy/deployment-runtime-config-openshift.yaml

# Update Provider to use runtime config
oc patch provider aap-crossplane-provider --type=merge -p '
spec:
  runtimeConfigRef:
    name: openshift-runtime-config
'
```

### Multiple ProviderConfigs

For managing multiple AAP instances:

```bash
# Create second credentials secret
export AAP_HOST="https://aap-prod.example.com"
export AAP_TOKEN="prod-token"
oc create secret generic aap-credentials-prod \
  -n crossplane-system \
  --from-literal=credentials="{\"host\":\"${AAP_HOST}\",\"token\":\"${AAP_TOKEN}\",\"insecure_skip_verify\":false}"

# Create second ProviderConfig
cat <<EOF | oc apply -f -
apiVersion: aap.aap.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: production
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: aap-credentials-prod
      key: credentials
EOF

# Use in managed resource
cat <<EOF | oc apply -f -
apiVersion: aap.aap.crossplane.io/v1alpha1
kind: Inventory
metadata:
  name: prod-inventory
spec:
  forProvider:
    name: production-inventory
    organization: 1
  providerConfigRef:
    name: production  # Uses production AAP instance
EOF
```

## Step 8: Monitoring and Troubleshooting

### Check Provider Health

```bash
# Provider status
oc get provider aap-crossplane-provider -o yaml

# Provider pod logs
oc logs -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider --tail=100 -f

# Provider pod events
oc get events -n crossplane-system --sort-by='.lastTimestamp' | grep provider
```

### Common Issues and Solutions

#### Issue: "state_upgraders" error in logs

**Symptom**:
```
Error: Plugin did not respond
  with null_resource.state_upgraders,
  on <empty> line 0:
  (source code not available)
```

**Cause**: Known Upjet bug with Terraform state management (terraform-plugin-sdk v2.35.0+).

**Solution**: This is a warning that appears but doesn't prevent functionality. Monitor resource status:
```bash
oc get inventory example-inventory
# If READY=True and SYNCED=True, the resource is working despite the error
```

**Workaround**: Pin terraform-plugin-sdk to v2.34.0 in provider dependencies (requires provider rebuild).

#### Issue: Resources not reconciling

**Symptom**: Inventory stays in "False False" state.

**Debug steps**:
```bash
# Check managed resource conditions
oc describe inventory example-inventory

# Look for error conditions:
# - ReconcileError: Configuration issue
# - ReconcileSuccess: False: API communication issue

# Check provider can reach AAP
oc exec -n crossplane-system deployment/<provider-deployment> -- \
  curl -v http://aap.ansible-automation-platform.svc.cluster.local/api/

# Expected: HTTP 200 with API version info
```

**Solution**:
- Verify AAP_HOST in credentials secret
- Check token is valid and not expired
- Ensure AAP service is accessible from crossplane-system namespace
- Verify organization ID exists in AAP

#### Issue: Provider pod restarting

**Check pod resource limits**:
```bash
oc describe pod -n crossplane-system <provider-pod-name>

# If OOMKilled:
# 1. Apply deployment-runtime-config-openshift.yaml with higher limits
# 2. Patch provider to use runtime config
```

### View Terraform State

The provider stores Terraform state in managed resource annotations:

```bash
# Get full resource with state
oc get inventory example-inventory -o yaml | grep -A 50 "upjet.crossplane.io/provider-meta"
```

## Step 9: Cleanup

```bash
# Delete managed resources first
oc delete inventory --all

# Wait for deletion to complete
oc wait --for=delete inventory --all --timeout=2m

# Delete ProviderConfig
oc delete providerconfig default

# Delete provider
oc delete provider aap-crossplane-provider

# Delete credentials secret
oc delete secret aap-credentials -n crossplane-system

# Optional: Uninstall Crossplane
helm uninstall crossplane -n crossplane-system
oc delete namespace crossplane-system
```

## Reference Configuration Summary

Successful deployment configuration (tested 2026-03-31):

| Component | Value |
|-----------|-------|
| Cluster | OpenShift 4.21.6 (chadsno2026.fteam.local) |
| Architecture | linux/amd64 |
| Crossplane | 2.2.0 |
| Provider Image | quay.io/cferman/provider-aap:0.1.15-multiarch |
| Terraform | 1.5.7 |
| Terraform AAP Provider | 1.4.0 |
| AAP Version | 2.6 (ansible-automation-platform namespace) |
| AAP Service | http://aap.ansible-automation-platform.svc.cluster.local |
| Auth Method | Application Token |
| Test Resource | Inventory (successfully created) |

## Next Steps

- [Example Resources](../../examples/) - More example manifests
- [Multi-Arch Build Guide](../build/MULTIARCH-BUILD.md) - Build your own images
- [AAP Provider Validation](VALIDATE-AAP-PROVIDER-API.md) - Test AAP API connectivity
- [Deployment Test Report](../../DEPLOYMENT_TEST_REPORT.md) - Detailed test results

## Additional Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [AAP Operator on OpenShift](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/)
- [Upjet Provider Development](https://github.com/crossplane/upjet)
- [Terraform AAP Provider](https://registry.terraform.io/providers/ansible/aap/latest/docs)
