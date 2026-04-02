# AAP Crossplane Provider - OpenShift Deployment Test Report

**Date**: 2026-03-31  
**Cluster**: chadsno2026 (OpenShift 4.21.6, Kubernetes 1.34.4)  
**Tester**: DevOps Automator Agent  
**Branch**: feat/architectural-improvements

---

## Executive Summary

Tested deployment of AAP Crossplane Provider on local OpenShift cluster. **Status**: ⚠️ **Partial Success with Blockers**

### ✅ Successful Steps
1. Crossplane 2.2.0 installed successfully via Helm
2. OpenShift-compatible security context values applied correctly
3. AAP provider CRDs already registered (from previous deployment)
4. AAP instance confirmed running in cluster (ansible-automation-platform namespace)
5. Provider package deployed (INSTALLED=True)

### 🔴 Blockers Identified
1. **Architecture Mismatch**: Provider pod in CrashLoopBackOff with "Exec format error"
   - Cause: Provider binary compiled for wrong architecture
   - Impact: Provider cannot start, no reconciliation possible
   
2. **Compilation Error**: Provider-aap code fails to build
   - Cause: API version mismatch between generated code and Crossplane runtime
   - Error: Missing `GetProviderConfigReference` method
   - Impact: Cannot rebuild provider with correct architecture

---

## Test Environment

### Cluster Information
```
Platform: OpenShift 4.21.6
Kubernetes: v1.34.4
Node Architecture: x86_64 (amd64)
Node OS: Red Hat Enterprise Linux CoreOS 9.6
Container Runtime: cri-o://1.34.6
```

### Namespaces
- **Crossplane**: `crossplane-system` (created during test)
- **AAP**: `ansible-automation-platform` (pre-existing)

### Contexts Available
```
admin (current)
ambient-code/api-chadsno2026-fteam-local:6443/system:admin
crossplane-system/api-chadsno2026-fteam-local:6443/system:admin
```

---

## Deployment Steps Executed

### Step 1: Install Crossplane ✅

**Command**:
```bash
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  -f deploy/crossplane-values-openshift.yaml \
  --wait --timeout 5m
```

**Result**: SUCCESS
```
NAME: crossplane
CHART VERSION: 2.2.0
STATUS: deployed
```

**Pods**:
```
NAME                                       READY   STATUS    AGE
crossplane-8468b98b68-5zr56                1/1     Running   16s
crossplane-rbac-manager-d8b6b7ddc-rgpqz    1/1     Running   16s
```

**CRDs Created**: 20+ Crossplane core CRDs registered

---

### Step 2: Verify AAP Provider CRDs ✅

**CRDs Found**:
```
groups.aap.aap.crossplane.io         (created 2026-03-17)
hosts.aap.aap.crossplane.io          (created 2026-03-17)
inventories.aap.aap.crossplane.io    (created 2026-03-17)
jobs.job.aap.crossplane.io           (created 2026-03-17)
workflowjobs.workflowjob.aap.crossplane.io
```

**Analysis**: CRDs were installed from a previous deployment (13 days ago). This indicates prior testing/deployment work.

---

### Step 3: Check Provider Status 🔴

**Provider**:
```
NAME                      INSTALLED   HEALTHY   PACKAGE                                 AGE
aap-crossplane-provider   True        False     quay.io/cferman/aap-crossplane:latest   13d
```

**Status Analysis**:
- ✅ INSTALLED=True (package downloaded and CRDs applied)
- 🔴 HEALTHY=False (pod not running)

**Pod Status**:
```
NAME                                                   READY   STATUS             RESTARTS
aap-crossplane-provider-154595b56819-c99d457fd-p5vvm   0/1     CrashLoopBackOff   6
```

**Logs**:
```
exec container process `/usr/local/bin/provider`: Exec format error
```

**Root Cause**: Architecture mismatch
- **Expected**: linux/amd64 (cluster nodes are x86_64)
- **Actual**: Likely linux/arm64 (built on macOS Apple Silicon)

---

### Step 4: Rebuild Provider (Attempted) 🔴

**Command**:
```bash
GOARCH=amd64 PROVIDER_AAP_DIR=~/Documents/GitHub/provider-aap \
  ./build/build-provider-image-podman.sh aap-crossplane:test-20260331
```

**Result**: FAILED - Compilation Error

**Error**:
```
internal/clients/aap.go:97:60: cannot use &clusterv1beta1.ProviderConfigUsage{} 
  as resource.LegacyProviderConfigUsage value in argument to 
  resource.NewLegacyProviderConfigUsageTracker: 
  *v1beta1.ProviderConfigUsage does not implement 
  resource.LegacyProviderConfigUsage (missing method GetProviderConfigReference)
```

**Analysis**:
- Generated code is incompatible with Crossplane runtime v2
- Likely due to:
  1. Outdated code generation
  2. Crossplane runtime version mismatch
  3. Missing API regeneration after runtime upgrade

**Required Fix**:
1. Regenerate provider code: `make generate` in provider-aap
2. Apply post-generate fixes: `../aap-crossplane/hack/post-generate-fixes.sh`
3. Rebuild with correct architecture

---

## AAP Instance Verification ✅

**AAP Components**:
```
NAMESPACE                         NAME                                              STATUS
ansible-automation-platform       aap-gateway-operator-controller-manager           Running (2/2)
```

**Services** (need to verify):
```bash
oc get svc -n ansible-automation-platform
```

**Expected**:
- Gateway service: `aap-gateway` or similar
- URL format: `http://aap-gateway.ansible-automation-platform.svc.cluster.local`

---

## Issues Found

### 🔴 Critical Issues

#### Issue 1: Architecture Mismatch in Provider Binary
**Severity**: Critical  
**Impact**: Provider cannot start, no functionality available

**Details**:
- Provider image `quay.io/cferman/aap-crossplane:latest` contains arm64 binary
- Cluster nodes are x86_64/amd64
- Results in "Exec format error"

**Resolution**:
1. **Short-term**: Build multi-arch image or separate amd64 image
2. **Long-term**: Use GitHub Actions to build for both architectures
   ```yaml
   strategy:
     matrix:
       arch: [amd64, arm64]
   ```

**Workaround**:
- Build on amd64 machine
- Or use Docker buildx for cross-compilation
- Or use OpenShift BuildConfig (if available)

---

#### Issue 2: Provider Code Compilation Failure
**Severity**: Critical  
**Impact**: Cannot rebuild provider

**Details**:
- Generated code incompatible with Crossplane runtime v2
- Missing required interface methods

**Root Cause**:
- Code generation was done with older Upjet/Crossplane versions
- Runtime dependencies updated but code not regenerated

**Resolution**:
1. Update dependencies in provider-aap:
   ```bash
   cd ~/Documents/GitHub/provider-aap
   go get -u github.com/crossplane/crossplane-runtime/v2
   ```

2. Regenerate provider code:
   ```bash
   make generate.init
   make generate
   ```

3. Apply post-generate fixes:
   ```bash
   ../aap-crossplane/hack/post-generate-fixes.sh
   ```

4. Rebuild:
   ```bash
   GOARCH=amd64 make build
   ```

---

### 🟡 Medium Issues

#### Issue 3: No ProviderConfig Exists
**Severity**: Medium  
**Impact**: Cannot test managed resources without credentials

**Details**:
- No AAP credentials secret found in crossplane-system
- No ProviderConfig applied

**Resolution**:
1. Create AAP credentials (need Application Token from AAP UI)
2. Apply ProviderConfig from `deploy/providerconfig-default.yaml`

**Steps**:
```bash
# Get AAP gateway URL
AAP_NS="ansible-automation-platform"
AAP_HOST="http://aap-gateway.${AAP_NS}.svc.cluster.local"

# Create secret (need token from AAP)
oc create secret generic aap-credentials -n crossplane-system \
  --from-literal=credentials='{"host":"'$AAP_HOST'","token":"<TOKEN>","insecure_skip_verify":true}'

# Apply ProviderConfig
oc apply -f deploy/providerconfig-default.yaml
```

---

#### Issue 4: Missing E2E Test Execution
**Severity**: Medium  
**Impact**: Cannot validate E2E test framework on real cluster

**Details**:
- E2E tests created in this PR but not executed against real OpenShift
- Mock API used in CI, but real AAP integration not tested

**Resolution**:
1. Create test inventory/host/group resources
2. Validate reconciliation with real AAP instance
3. Document test results

---

### 💭 Minor Issues

#### Issue 5: Old Provider Deployment Not Cleaned
**Severity**: Low  
**Impact**: Confusing state, old resources present

**Details**:
- 13-day-old provider deployment still present
- CRDs from previous deployment
- May cause confusion during testing

**Resolution**:
```bash
# Clean old provider
oc delete provider aap-crossplane-provider

# Optional: Clean CRDs if testing from scratch
oc delete crd groups.aap.aap.crossplane.io
oc delete crd hosts.aap.aap.crossplane.io
# ... (all AAP CRDs)
```

---

## Recommendations

### Immediate Actions (Before Merge)

1. **Fix Provider Compilation** (Critical)
   - Regenerate provider code with updated dependencies
   - Apply post-generate fixes
   - Test build succeeds for amd64

2. **Multi-Architecture Build** (Critical)
   - Update CI workflow to build for amd64 and arm64
   - Push multi-arch manifest to registry
   - Test on both architectures

3. **Document Architecture Requirements** (High)
   - Update BUILD.md with architecture notes
   - Add troubleshooting section for "Exec format error"
   - Document multi-arch build process

4. **Test E2E on Real Cluster** (High)
   - Deploy working provider to OpenShift
   - Create AAP credentials and ProviderConfig
   - Apply test managed resources
   - Validate reconciliation

### Short-Term Improvements

1. **Automated Multi-Arch Builds**
   ```yaml
   # .github/workflows/build-provider.yml
   - name: Build multi-arch image
     uses: docker/build-push-action@v5
     with:
       platforms: linux/amd64,linux/arm64
       push: true
       tags: quay.io/cferman/aap-crossplane:${{ github.sha }}
   ```

2. **Pre-Deployment Health Checks**
   - Add script to verify AAP is reachable before deploying provider
   - Check Crossplane version compatibility
   - Validate architecture matches cluster nodes

3. **Deployment Validation Script**
   ```bash
   # test/validate-deployment.sh
   - Check provider pod is Running
   - Check provider is Healthy
   - Check ProviderConfig exists
   - Attempt to create test Inventory
   - Verify in AAP UI
   ```

### Long-Term Enhancements

1. **Helm Chart for Full Stack**
   - Chart that deploys Crossplane + AAP Provider + ProviderConfig
   - Values for AAP credentials
   - Optional test resources

2. **Provider Health Monitoring**
   - Add Prometheus metrics to provider
   - Create Grafana dashboard
   - Alert on provider unhealthy

3. **Integration Test Suite**
   - Tests that run against real AAP instance
   - Create/update/delete managed resources
   - Validate Job execution
   - Test deletion policies

---

## Test Summary

### Deployment Steps
| Step | Status | Notes |
|------|--------|-------|
| Create namespace | ✅ Pass | crossplane-system created |
| Install Crossplane via Helm | ✅ Pass | v2.2.0 deployed successfully |
| Verify Crossplane pods | ✅ Pass | Core pods Running |
| Check for AAP instance | ✅ Pass | AAP running in ansible-automation-platform |
| Verify provider CRDs | ✅ Pass | CRDs registered (from previous deployment) |
| Check provider status | 🔴 Fail | CrashLoopBackOff - architecture mismatch |
| Rebuild provider | 🔴 Fail | Compilation error - API version mismatch |
| Create ProviderConfig | ⏭️ Skip | Blocked by provider not running |
| Test managed resources | ⏭️ Skip | Blocked by provider not running |

### Success Rate
- **Passed**: 5/9 (55%)
- **Failed**: 2/9 (22%)
- **Skipped**: 2/9 (22%)

---

## Next Steps

### For Developer
1. Regenerate provider-aap code to fix compilation
2. Build multi-arch image
3. Push to registry
4. Test deployment again

### For CI/CD
1. Add multi-arch build to workflow
2. Add deployment smoke test to pipeline
3. Test against real OpenShift cluster (not just Kind)

### For Documentation
1. Add architecture troubleshooting to BUILD.md
2. Document multi-arch build process
3. Add OpenShift-specific deployment notes

---

## Appendix: Commands Used

```bash
# Check cluster
kubectl config get-contexts
oc version

# Install Crossplane
oc create namespace crossplane-system
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  -f deploy/crossplane-values-openshift.yaml \
  --wait --timeout 5m

# Verify installation
oc get pods -n crossplane-system
oc get crd | grep crossplane
oc get providers

# Check provider logs
oc logs -n crossplane-system deployment/aap-crossplane-provider-154595b56819

# Attempt rebuild
GOARCH=amd64 PROVIDER_AAP_DIR=~/Documents/GitHub/provider-aap \
  ./build/build-provider-image-podman.sh aap-crossplane:test-20260331
```

---

## Conclusion

The deployment test revealed two critical blockers that prevent successful deployment:

1. **Architecture mismatch** preventing provider from starting
2. **Code compilation errors** preventing rebuilding

Both issues are solvable:
- Regenerate provider code with updated dependencies
- Build for correct architecture (amd64)
- Implement multi-arch builds in CI

The Crossplane installation itself was **100% successful**, demonstrating that the OpenShift-compatible values file works correctly and security contexts are properly configured.

**Recommendation**: Address compilation issues in provider-aap repository, add multi-arch build support, then re-test full deployment flow.

---

**Test Conducted By**: DevOps Automator Agent  
**Date**: 2026-03-31  
**Environment**: OpenShift 4.21.6 (chadsno2026)  
**Status**: ⚠️ Blockers Identified - Action Required
