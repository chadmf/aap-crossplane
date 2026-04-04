# Multi-Arch Deployment Quick Reference

Fast reference for deploying the multi-arch AAP Crossplane provider to OpenShift.

## Prerequisites Checklist

- [ ] OpenShift 4.12+ cluster access
- [ ] AAP 2.5+ running (in-cluster or external)
- [ ] AAP Application Token created
- [ ] `oc` CLI configured

## 5-Minute Deployment

### 1. Install Crossplane (if not already installed)

```bash
oc create namespace crossplane-system
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  -f deploy/crossplane-values-openshift.yaml \
  --wait --timeout 5m
```

### 2. Deploy Provider

```bash
cat <<EOF | oc apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: aap-crossplane-provider
spec:
  package: quay.io/cferman/provider-aap:0.1.15-multiarch
  revisionActivationPolicy: Automatic
EOF

# Wait for installation
oc wait provider aap-crossplane-provider --for=condition=Installed=True --timeout=5m
```

### 3. Configure AAP Credentials

```bash
# Set your AAP details
export AAP_HOST="http://aap.ansible-automation-platform.svc.cluster.local"
export AAP_TOKEN="your-token-here"  # From AAP UI → Users → Tokens

# Create secret
oc create secret generic aap-credentials -n crossplane-system \
  --from-literal=credentials="{\"host\":\"${AAP_HOST}\",\"token\":\"${AAP_TOKEN}\",\"insecure_skip_verify\":true}"
```

### 4. Apply ProviderConfig

```bash
oc apply -f deploy/providerconfig-default.yaml
```

### 5. Test with Example Inventory

```bash
oc apply -f examples/example-inventory.yaml

# Watch status
oc get inventory example-inventory -w
# Wait for: READY=True, SYNCED=True
```

## Verify Deployment

```bash
# Check provider is healthy
oc get provider aap-crossplane-provider
# Expected: INSTALLED=True, HEALTHY=True

# Check provider pod
oc get pods -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider
# Expected: STATUS=Running

# Check inventory in AAP
# AAP UI → Resources → Inventories → Look for "crossplane-example-inventory"
```

## Troubleshooting Commands

```bash
# Provider pod logs
oc logs -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider --tail=50

# Provider status details
oc describe provider aap-crossplane-provider

# Inventory resource details
oc describe inventory example-inventory

# Check architecture match
oc get nodes -o wide  # Check ARCHITECTURE column
podman manifest inspect quay.io/cferman/provider-aap:0.1.15-multiarch  # Check image platforms
```

## Common Issues Quick Fix

### Issue: CrashLoopBackOff with "Exec format error"

**Fix**: Image architecture doesn't match cluster. Use multi-arch image:
```bash
oc patch provider aap-crossplane-provider --type=merge -p '{"spec":{"package":"quay.io/cferman/provider-aap:0.1.15-multiarch"}}'
```

### Issue: Provider pod logs show "terraform: command not found"

**Fix**: Image missing Terraform. Rebuild with Terraform included (see MULTIARCH-BUILD.md).

### Issue: Inventory stays READY=False

**Fix**: Check AAP connectivity:
```bash
# From within cluster
oc run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://aap.ansible-automation-platform.svc.cluster.local/api/
# Should return HTTP 200 with API info
```

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `AAP_HOST` | AAP gateway URL (no /api/controller suffix) | `http://aap.ansible-automation-platform.svc.cluster.local` |
| `AAP_TOKEN` | Application token from AAP UI | `abcd1234...` |
| `AAP_CROSSPLANE` | Alternative to AAP_TOKEN | `abcd1234...` |
| `PROVIDER_AAP_DIR` | Path to provider source (for builds) | `~/Documents/GitHub/provider-aap` |

## Service URL Patterns

### In-Cluster AAP (Recommended)

```bash
# AAP 2.5+ gateway service
http://aap.ansible-automation-platform.svc.cluster.local

# Alternative gateway service names
http://aap-gateway.ansible-automation-platform.svc.cluster.local
http://aap-api.ansible-automation-platform.svc.cluster.local
```

### External AAP

```bash
# Public route (HTTPS with valid cert)
https://aap.example.com

# Self-signed cert (set insecure_skip_verify: true)
https://aap-dev.internal.example.com
```

## Example Resources

All examples in `examples/` directory:

```bash
# Inventory only
oc apply -f examples/example-inventory.yaml

# Inventory with host
oc apply -f examples/example-inventory-with-host.yaml

# Job template
oc apply -f examples/example-job-template.yaml

# Job execution
oc apply -f examples/example-job.yaml
```

## Cleanup Commands

```bash
# Delete managed resources
oc delete inventory --all
oc delete host --all
oc delete group --all

# Delete provider
oc delete providerconfig default
oc delete provider aap-crossplane-provider

# Delete credentials
oc delete secret aap-credentials -n crossplane-system
```

## Version Information

**Current Multi-Arch Release**: 0.1.15-multiarch

| Component | Version |
|-----------|---------|
| Provider Image | quay.io/cferman/provider-aap:0.1.15-multiarch |
| Terraform | 1.5.7 |
| Terraform AAP Provider | 1.4.0 |
| Crossplane | 2.2.0+ |
| AAP | 2.5+ |
| Architectures | linux/amd64, linux/arm64 |

## Full Documentation

- [Multi-Arch Build Guide](build/MULTIARCH-BUILD.md) - Build your own images
- [OpenShift Deployment Guide](deploy/OPENSHIFT-MULTIARCH-DEPLOYMENT.md) - Complete deployment walkthrough
- [Main README](../README.md) - Architecture and design overview
- [Build Documentation](../BUILD.md) - Provider development and generation

## Support

For issues or questions:
1. Check provider pod logs: `oc logs -n crossplane-system -l pkg.crossplane.io/provider=aap-crossplane-provider`
2. Review [DEPLOYMENT_TEST_REPORT.md](../DEPLOYMENT_TEST_REPORT.md) for known issues
3. See [docs/deploy/VALIDATE-AAP-PROVIDER-API.md](deploy/VALIDATE-AAP-PROVIDER-API.md) for API validation

## Success Criteria

Deployment is successful when:
- [ ] Provider pod STATUS=Running
- [ ] Provider HEALTHY=True
- [ ] Test inventory READY=True, SYNCED=True
- [ ] Inventory visible in AAP UI
- [ ] No "Exec format error" in logs
- [ ] No "terraform: command not found" in logs
