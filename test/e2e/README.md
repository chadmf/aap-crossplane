># End-to-End Testing

This directory contains end-to-end (E2E) tests for the AAP Crossplane Provider.

## Overview

E2E tests validate the complete provider lifecycle:

1. **Kind cluster setup** - Creates isolated Kubernetes environment
2. **Crossplane installation** - Installs Crossplane control plane
3. **Mock AAP API** - Deploys minimal AAP API simulator for testing
4. **Provider deployment** - Builds and installs the AAP provider
5. **Resource validation** - Applies test MRs and validates status conditions
6. **CRD verification** - Ensures all expected CRDs are registered

## Prerequisites

```bash
# Required
go install sigs.k8s.io/kind@latest
kubectl version --client
helm version

# Provider directory (sibling to aap-crossplane)
export PROVIDER_AAP_DIR=../provider-aap
```

## Quick Start

```bash
# Run full E2E test suite
./test/e2e/run-e2e-tests.sh

# Run and cleanup cluster after
./test/e2e/run-e2e-tests.sh --cleanup

# Skip provider build (use existing image)
./test/e2e/run-e2e-tests.sh --skip-build
```

## Test Scenarios

### 1. Build Pipeline Validation

Verifies that:
- ✅ Post-generate fixes apply cleanly
- ✅ Provider binary builds successfully
- ✅ Container image can be created

### 2. CRD Registration

Validates that all expected CRDs are created:
- `inventories.inventory.aap.crossplane.io`
- `hosts.host.aap.crossplane.io`
- `groups.group.aap.crossplane.io`
- `jobs.job.aap.crossplane.io`
- `workflowjobs.workflowjob.aap.crossplane.io`

### 3. Provider Health

Checks that:
- Provider pod starts successfully
- Provider becomes `Installed=True`
- Provider becomes `Healthy=True`
- ProviderConfig is accepted

### 4. Managed Resource Lifecycle

Tests basic resource operations:
- Resource creation (apply YAML)
- Controller reconciliation
- Status condition updates
- Deletion policies (Orphan)

## Mock AAP API

The E2E tests use a minimal Python-based mock API that implements:

- **`GET /api/`** - Gateway discovery (returns controller/EDA endpoints)
- **`GET /api/gateway/v1/status/`** - Health check

**Limitations**:
- Does not implement full AAP REST API
- Resources will fail reconciliation (expected)
- Used only to validate provider startup and CRD handling

For full integration tests against real AAP, use the validation scripts in `deploy/testing-scripts/`.

## Customization

### Environment Variables

```bash
# Custom cluster name
export KIND_CLUSTER_NAME=my-e2e-cluster

# Custom Crossplane version
export CROSSPLANE_VERSION=1.15.0

# Custom provider image tag
export PROVIDER_IMAGE=aap-crossplane:custom-tag

# Provider directory location
export PROVIDER_AAP_DIR=/path/to/provider-aap
```

### Test Resources

Add test MRs to `test/e2e/manifests/` (create directory):

```yaml
# test/e2e/manifests/test-inventory.yaml
apiVersion: inventory.aap.crossplane.io/v1alpha1
kind: Inventory
metadata:
  name: test-inventory
spec:
  forProvider:
    name: "Test Inventory"
    organizationId: 1
  providerConfigRef:
    name: default
```

## CI/CD Integration

### GitHub Actions

The `.github/workflows/e2e-tests.yml` workflow runs E2E tests on:
- Pull requests affecting provider code
- Pushes to `main`
- Manual workflow dispatch

**What it validates**:
- Code generation completes without errors
- Post-generate fixes apply successfully
- Provider builds and starts
- CRDs are registered
- Basic resource lifecycle works

### Expected Error Signatures

Since the mock API is minimal, these errors are **expected**:

```
# Resource reconciliation failures (mock API incomplete)
"Failed to observe managed resource: GET /api/controller/v2/inventories/1 returned 404"

# Terraform state errors (no real backend)
"terraform apply failed: resource not found"
```

**Unexpected errors** that indicate real issues:

```
# Provider startup failures
"provider pod CrashLoopBackOff"
"ProviderConfig validation failed"

# CRD registration issues
"no matches for kind Inventory in version inventory.aap.crossplane.io/v1alpha1"

# Controller panics
"controller runtime error: nil pointer dereference"
```

## Debugging Failed Tests

### Inspect cluster state

```bash
# Get cluster context
kubectl cluster-info --context kind-aap-provider-e2e

# Check provider status
kubectl get providers
kubectl describe provider provider-aap

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aap

# Check managed resources
kubectl get inventories
kubectl describe inventory test-inventory
```

### Preserve cluster for debugging

```bash
# Run without cleanup flag
./test/e2e/run-e2e-tests.sh

# Cluster remains running for inspection
# Delete manually when done
kind delete cluster --name aap-provider-e2e
```

### Test individual components

```bash
# Test only build pipeline
cd $PROVIDER_AAP_DIR
make generate.init
make generate
$OLDPWD/hack/post-generate-fixes.sh
make build

# Test only CRD application
kubectl apply -f $PROVIDER_AAP_DIR/package/crds/
kubectl get crds | grep aap

# Test only provider installation
kind load docker-image aap-crossplane:e2e-test --name aap-provider-e2e
kubectl apply -f deploy/provider.yaml
kubectl wait --for=condition=Healthy provider/provider-aap
```

## Troubleshooting

### "Provider directory not found"

```bash
# Set PROVIDER_AAP_DIR
export PROVIDER_AAP_DIR=/path/to/provider-aap
./test/e2e/run-e2e-tests.sh
```

### "Kind cluster creation failed"

```bash
# Cleanup stale clusters
kind get clusters
kind delete cluster --name aap-provider-e2e

# Check Docker/Podman is running
docker ps
```

### "Provider pod fails to start"

```bash
# Check logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aap

# Common issues:
# - Image pull failed: ensure image was loaded into Kind
# - CrashLoopBackOff: check for nil pointer or import errors
# - ImagePullBackOff: verify image tag matches manifest
```

### "CRDs not found"

```bash
# Verify generation completed
ls $PROVIDER_AAP_DIR/package/crds/

# Check if provider installed CRDs
kubectl get crds | grep aap

# If missing, provider may have failed startup
kubectl describe provider provider-aap
```

## Related Documentation

- [Build Documentation](../../BUILD.md) - Provider build process
- [Post-Generate Fixes](../../hack/post-generate-fixes.sh) - Automated fixes
- [ADR-001](../../docs/adr/ADR-001-upjet-vs-native.md) - Upjet decision rationale
- [Validation Scripts](../../deploy/testing-scripts/) - Real AAP API testing

## Contributing

When adding new resources:

1. Add resource to `provider/config/`
2. Regenerate provider: `make generate`
3. Apply post-gen fixes: `hack/post-generate-fixes.sh`
4. Update E2E tests to validate new CRD
5. Add example MR to `examples/`
6. Update expected CRD list in `run-e2e-tests.sh`

When modifying post-generate fixes:

1. Test against clean provider template clone
2. Verify `make build` succeeds after fixes
3. Run E2E tests to validate end-to-end
4. Document fix rationale in script comments
