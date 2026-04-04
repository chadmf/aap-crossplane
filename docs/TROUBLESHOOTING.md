# AAP Crossplane Provider Troubleshooting Guide

Comprehensive troubleshooting guide for common issues with the AAP Crossplane provider deployment.

## Architecture and Build Issues

### Issue: Exec format error (CrashLoopBackOff)

**Symptom**:
```bash
$ oc get pods -n crossplane-system
NAME                                              READY   STATUS             RESTARTS   AGE
aap-crossplane-provider-xxx-xxx                   0/1     CrashLoopBackOff   5          2m

$ oc logs aap-crossplane-provider-xxx-xxx
exec container process `/usr/local/bin/provider`: Exec format error
```

**Cause**: The provider binary was compiled for a different architecture than the cluster nodes (e.g., arm64 binary on amd64 cluster).

**Diagnosis**:
```bash
# Check cluster node architecture
oc get nodes -o wide
# Look at ARCHITECTURE column (amd64 or arm64)

# Check image architecture
podman manifest inspect quay.io/cferman/provider-aap:0.1.15-multiarch | jq '.manifests[].platform'
# Should show both linux/amd64 and linux/arm64
```

**Solution**:
```bash
# Option 1: Use multi-arch image
oc patch provider aap-crossplane-provider --type=merge -p '
spec:
  package: quay.io/cferman/provider-aap:0.1.15-multiarch
'

# Option 2: Build for specific architecture
cd ~/Documents/GitHub/provider-aap
GOARCH=amd64 make build
# Then push image and update provider
```

**Prevention**: Always build multi-arch images for production. See [MULTIARCH-BUILD.md](build/MULTIARCH-BUILD.md).

---

### Issue: terraform: command not found

**Symptom**:
```bash
$ oc logs aap-crossplane-provider-xxx-xxx
Error: failed to initialize Terraform: exec: "terraform": executable file not found in $PATH
```

**Cause**: The container image doesn't include Terraform binary.

**Diagnosis**:
```bash
# Check if image was built with Terraform
podman run --rm --entrypoint sh quay.io/cferman/provider-aap:0.1.15-multiarch -c "which terraform"
# Should output: /usr/local/bin/terraform
```

**Solution**: Rebuild the provider image with Terraform included. The proper Dockerfile must include:

```dockerfile
# Download and install Terraform
ARG TERRAFORM_VERSION=1.5.7
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip -o terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/ && \
    rm terraform.zip
```

**Note**: The `build/build-provider-multi-arch.sh` script only builds the Go binary without Terraform. Use the provider's Makefile or ensure your Dockerfile includes Terraform installation.

See [MULTIARCH-BUILD.md](build/MULTIARCH-BUILD.md) for correct build process.

---

### Issue: terraform-provider-aap not found

**Symptom**:
```bash
Error: provider registry.terraform.io/ansible/aap could not be found
```

**Cause**: Terraform AAP provider plugin not pre-installed in image.

**Solution**: Ensure Dockerfile includes Terraform provider download:

```dockerfile
ARG TERRAFORM_PROVIDER_VERSION=1.4.0
RUN mkdir -p /root/.terraform.d/plugins && \
    curl -fsSL https://github.com/ansible/terraform-provider-aap/releases/download/v${TERRAFORM_PROVIDER_VERSION}/terraform-provider-aap_${TERRAFORM_PROVIDER_VERSION}_linux_${TARGETARCH}.zip -o provider.zip && \
    unzip provider.zip -d /root/.terraform.d/plugins && \
    rm provider.zip
```

---

## Provider Installation Issues

### Issue: Provider stays INSTALLED=False

**Symptom**:
```bash
$ oc get provider aap-crossplane-provider
NAME                      INSTALLED   HEALTHY   PACKAGE
aap-crossplane-provider   False       Unknown   quay.io/...
```

**Diagnosis**:
```bash
# Get detailed status
oc describe provider aap-crossplane-provider

# Check provider revision
oc get providerrevision
```

**Common Causes**:

1. **Image pull error** (401 Unauthorized)
   ```bash
   # Solution: Create image pull secret
   oc create secret docker-registry quay-pull-secret \
     -n crossplane-system \
     --docker-server=quay.io \
     --docker-username=youruser \
     --docker-password=yourtoken
   
   # Update provider
   oc patch provider aap-crossplane-provider --type=merge -p '
   spec:
     packagePullSecrets:
       - name: quay-pull-secret
   '
   ```

2. **CRD installation timeout**
   ```bash
   # Check CRD status
   oc get crd | grep aap
   
   # If CRDs exist from old deployment, they may have stale ownerReferences
   # See "Stale CRD OwnerReferences" section below
   ```

3. **Invalid package format**
   - Ensure using provider image (not xpkg package format)
   - Provider packages must be built with Crossplane packaging tools

---

### Issue: Provider INSTALLED=True but HEALTHY=False

**Symptom**:
```bash
NAME                      INSTALLED   HEALTHY   PACKAGE
aap-crossplane-provider   True        False     quay.io/...
```

**Diagnosis**:
```bash
# Check provider revision details
oc describe providerrevision -l pkg.crossplane.io/provider=aap-crossplane-provider

# Look for condition message like:
# "cannot establish control of object ... already controlled by ProviderRevision ..."
```

**Common Causes**:

1. **Stale CRD OwnerReferences**

   When switching provider images or reinstalling, CRDs may have ownerReferences to deleted ProviderRevisions.

   ```bash
   # Check CRD owners
   oc get crd providerconfigs.aap.crossplane.io -o jsonpath='{.metadata.ownerReferences}{"\n"}'
   
   # If listed ProviderRevision doesn't exist
   oc get providerrevision <name>  # Should return NotFound
   
   # Remove stale ownerReferences
   oc patch crd providerconfigs.aap.crossplane.io --type=json \
     -p='[{"op": "remove", "path": "/metadata/ownerReferences"}]'
   
   # Repeat for all AAP CRDs
   for crd in inventories groups hosts jobs workflowjobs; do
     oc patch crd ${crd}.aap.aap.crossplane.io --type=json \
       -p='[{"op": "remove", "path": "/metadata/ownerReferences"}]'
   done
   ```

2. **Pod security context issues (OpenShift)**

   OpenShift requires specific security contexts. Use the OpenShift-compatible values:

   ```bash
   helm upgrade crossplane crossplane-stable/crossplane \
     --namespace crossplane-system \
     -f deploy/crossplane-values-openshift.yaml \
     --reuse-values
   ```

---

## Terraform State Management Issues

### Issue: "state_upgraders" error (Known Upjet Bug)

**Symptom**:
```bash
$ oc logs aap-crossplane-provider-xxx-xxx
Error: Plugin did not respond
  with null_resource.state_upgraders,
  on <empty> line 0:
  (source code not available)

The plugin encountered an error, and failed to respond to the plugin.(*GRPCProvider).UpgradeResourceState call.
```

**Cause**: This is a known issue in Upjet when using terraform-plugin-sdk v2.35.0+. The Terraform plugin tries to upgrade state schemas but encounters a null resource error.

**Impact**: 
- This error appears in logs but **does not prevent resource creation/management**
- Resources will still reconcile successfully
- The error is cosmetic and can be ignored

**Verification**:
```bash
# Check if resources are actually working despite the error
oc get inventory example-inventory

# If READY=True and SYNCED=True, resources are functioning correctly
# NAME                 READY   SYNCED   EXTERNAL-NAME   AGE
# example-inventory    True    True     123             2m
```

**Workaround** (if rebuilding provider):

In provider's `go.mod`, pin terraform-plugin-sdk to v2.34.0:
```go
require (
    github.com/hashicorp/terraform-plugin-sdk/v2 v2.34.0
    // ... other dependencies
)
```

Then rebuild:
```bash
cd ~/Documents/GitHub/provider-aap
go mod tidy
make build
```

**Status**: This is an upstream Upjet issue. Monitor:
- https://github.com/crossplane/upjet/issues
- https://github.com/hashicorp/terraform-plugin-sdk/issues

---

## Credentials and Connectivity Issues

### Issue: Resources stay READY=False, SYNCED=False

**Symptom**:
```bash
$ oc get inventory example-inventory
NAME                 READY   SYNCED   EXTERNAL-NAME   AGE
example-inventory    False   False                    5m

$ oc describe inventory example-inventory
Conditions:
  Type:   ReconcileError
  Message: cannot run Terraform: exit status 1
```

**Diagnosis**:
```bash
# Check provider logs
oc logs -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider --tail=100

# Look for error messages like:
# - "dial tcp: lookup aap.ansible-automation-platform.svc.cluster.local: no such host"
# - "401 Unauthorized"
# - "connection refused"
```

**Common Causes**:

1. **No ProviderConfig exists**
   ```bash
   oc get providerconfig
   # Should show at least one ProviderConfig (e.g., "default")
   
   # If missing, apply
   oc apply -f deploy/providerconfig-default.yaml
   ```

2. **No credentials secret**
   ```bash
   oc get secret aap-credentials -n crossplane-system
   # Should exist
   
   # If missing, create
   export AAP_HOST="http://aap.ansible-automation-platform.svc.cluster.local"
   export AAP_TOKEN="your-token"
   ./deploy/create-aap-credentials-secret.sh
   ```

3. **Wrong AAP host URL**
   
   Common mistakes:
   - Adding `/api/controller` suffix (don't do this)
   - Wrong service name
   - Wrong namespace
   
   Correct format:
   ```bash
   # In-cluster AAP (recommended)
   http://aap.ansible-automation-platform.svc.cluster.local
   
   # External AAP
   https://aap.example.com
   ```

4. **Invalid or expired token**
   ```bash
   # Test token manually
   AAP_HOST="http://aap.ansible-automation-platform.svc.cluster.local"
   AAP_TOKEN="your-token"
   
   oc run -it --rm test --image=curlimages/curl --restart=Never -- \
     curl -H "Authorization: Bearer ${AAP_TOKEN}" \
     ${AAP_HOST}/api/v2/me/
   
   # Should return user info, not 401
   ```

5. **AAP not reachable from crossplane-system namespace**
   ```bash
   # Test connectivity
   oc run -it --rm test --image=curlimages/curl --restart=Never -- \
     curl -v http://aap.ansible-automation-platform.svc.cluster.local/api/
   
   # Should return HTTP 200 with API info
   ```

---

### Issue: "insecure_skip_verify" SSL errors

**Symptom**:
```bash
Error: x509: certificate signed by unknown authority
```

**Cause**: AAP using self-signed certificate but `insecure_skip_verify` not set.

**Solution**:
```bash
# For self-signed certs or internal HTTP, set insecure_skip_verify: true
export AAP_HOST="https://aap.example.com"
export AAP_TOKEN="your-token"

oc create secret generic aap-credentials -n crossplane-system \
  --from-literal=credentials="{\"host\":\"${AAP_HOST}\",\"token\":\"${AAP_TOKEN}\",\"insecure_skip_verify\":true}" \
  --dry-run=client -o yaml | oc apply -f -
```

For production with valid certificates:
```json
{"host":"https://aap.example.com","token":"...","insecure_skip_verify":false}
```

---

## Resource Management Issues

### Issue: Resources created but not visible in AAP

**Diagnosis**:
```bash
# Check resource status
oc get inventory example-inventory -o yaml

# Look at status.atProvider for AAP resource ID
# Example:
# status:
#   atProvider:
#     id: "123"
#     name: "crossplane-example-inventory"
```

**Common Causes**:

1. **Wrong organization ID**
   
   Resources must be created in an existing organization:
   ```yaml
   spec:
     forProvider:
       organization: 1  # Must exist in AAP
   ```
   
   Find organization ID in AAP UI or via API:
   ```bash
   curl -H "Authorization: Bearer ${AAP_TOKEN}" \
     ${AAP_HOST}/api/v2/organizations/ | jq '.results[] | {id, name}'
   ```

2. **Resource in different organization than you're viewing**
   
   Check AAP UI organization selector and ensure viewing correct org.

---

### Issue: Cannot delete resources

**Symptom**:
```bash
$ oc delete inventory example-inventory
# Hangs, resource not deleted
```

**Diagnosis**:
```bash
# Check finalizers
oc get inventory example-inventory -o yaml | grep -A 5 finalizers

# Check for deletion timestamp
oc get inventory example-inventory -o yaml | grep deletionTimestamp
```

**Common Causes**:

1. **Finalizer stuck (AAP resource already deleted)**
   ```bash
   # Remove finalizer to force delete
   oc patch inventory example-inventory --type=json \
     -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
   ```

2. **Provider pod not running**
   ```bash
   # Check provider pod
   oc get pods -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider
   
   # If not running, fix provider first
   ```

---

## Performance and Resource Issues

### Issue: Provider pod OOMKilled or restarting

**Symptom**:
```bash
$ oc get pods -n crossplane-system
NAME                                    READY   STATUS      RESTARTS   AGE
aap-crossplane-provider-xxx-xxx         0/1     OOMKilled   3          5m
```

**Solution**: Increase memory limits via DeploymentRuntimeConfig:

```bash
# Apply runtime config with higher limits
oc apply -f deploy/deployment-runtime-config-openshift.yaml

# Patch provider to use it
oc patch provider aap-crossplane-provider --type=merge -p '
spec:
  runtimeConfigRef:
    name: openshift-runtime-config
'
```

Adjust limits in `deploy/deployment-runtime-config-openshift.yaml`:
```yaml
spec:
  deploymentTemplate:
    spec:
      template:
        spec:
          containers:
          - name: package-runtime
            resources:
              limits:
                memory: 2Gi  # Increase as needed
              requests:
                memory: 512Mi
```

---

## Diagnostic Commands Reference

### Provider Status
```bash
# Provider overview
oc get provider aap-crossplane-provider

# Detailed status
oc describe provider aap-crossplane-provider

# Provider revision
oc get providerrevision -l pkg.crossplane.io/provider=aap-crossplane-provider

# Provider pod
oc get pods -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider

# Provider logs
oc logs -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider --tail=100 -f
```

### Resource Status
```bash
# List all inventories
oc get inventory

# Detailed inventory status
oc describe inventory example-inventory

# Full resource YAML
oc get inventory example-inventory -o yaml

# Check conditions
oc get inventory example-inventory -o jsonpath='{.status.conditions}' | jq
```

### Connectivity Testing
```bash
# Test AAP API from cluster
oc run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl -v http://aap.ansible-automation-platform.svc.cluster.local/api/

# Test with authentication
oc run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl -H "Authorization: Bearer ${AAP_TOKEN}" \
  http://aap.ansible-automation-platform.svc.cluster.local/api/v2/me/

# Test from provider pod namespace
oc exec -n crossplane-system deployment/<provider-deployment> -- \
  curl -v http://aap.ansible-automation-platform.svc.cluster.local/api/
```

### Architecture Verification
```bash
# Cluster architecture
oc get nodes -o wide

# Image architecture
podman manifest inspect quay.io/cferman/provider-aap:0.1.15-multiarch | \
  jq '.manifests[].platform'

# Running pod architecture
oc get pod <provider-pod> -o jsonpath='{.status.containerStatuses[0].image}'
```

---

## Getting Help

If issues persist after trying these solutions:

1. **Collect diagnostic information**:
   ```bash
   # Provider status
   oc get provider aap-crossplane-provider -o yaml > provider-status.yaml
   
   # Provider logs
   oc logs -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider \
     --tail=500 > provider-logs.txt
   
   # Resource status
   oc get inventory -o yaml > inventories-status.yaml
   
   # CRD status
   oc get crd | grep aap > crds-list.txt
   ```

2. **Review test report**: [DEPLOYMENT_TEST_REPORT.md](../DEPLOYMENT_TEST_REPORT.md)

3. **Check documentation**:
   - [Multi-Arch Build Guide](build/MULTIARCH-BUILD.md)
   - [OpenShift Deployment Guide](deploy/OPENSHIFT-MULTIARCH-DEPLOYMENT.md)
   - [Quick Reference](MULTIARCH-QUICK-REFERENCE.md)

4. **File an issue** with diagnostic information attached
