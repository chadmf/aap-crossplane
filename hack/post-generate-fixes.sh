#!/usr/bin/env bash
# Post-generate fixes for Upjet AAP provider
#
# This script applies required fixes after running 'make generate' in the provider repo.
# It addresses package structure mismatches between Upjet generator expectations and
# the actual layout (cluster/namespaced scoping).
#
# Usage:
#   From provider repo: ../aap-crossplane/hack/post-generate-fixes.sh
#   Or set PROVIDER_AAP_DIR: PROVIDER_AAP_DIR=/path/to/provider-aap ./hack/post-generate-fixes.sh

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Determine provider directory
PROVIDER_DIR="${PROVIDER_AAP_DIR:-../provider-aap}"

if [[ ! -d "$PROVIDER_DIR" ]]; then
    log_error "Provider directory not found: $PROVIDER_DIR"
    log_error "Set PROVIDER_AAP_DIR or run from aap-crossplane repo with provider-aap as sibling"
    exit 1
fi

cd "$PROVIDER_DIR"
log_info "Applying post-generate fixes to $(pwd)"

# Get the module path from go.mod
MODULE_PATH=$(go mod edit -json | grep -A1 '"Module"' | grep '"Path"' | cut -d'"' -f4)
if [[ -z "$MODULE_PATH" ]]; then
    MODULE_PATH="github.com/crossplane-contrib/provider-aap"
    log_warn "Could not detect module path, using default: $MODULE_PATH"
fi
log_info "Module path: $MODULE_PATH"

# Fix 1: apis/zz_register.go - Fix imports to use cluster packages
log_info "Fix 1: Updating apis/zz_register.go imports..."

if [[ -f "apis/zz_register.go" ]]; then
    # Backup original
    cp apis/zz_register.go apis/zz_register.go.bak

    # Fix imports using sed
    sed -i.tmp -E \
        -e "s|v1alpha1apis \"${MODULE_PATH}/apis/v1alpha1\"|clusterv1alpha1 \"${MODULE_PATH}/apis/cluster/v1alpha1\"|g" \
        -e "s|v1beta1 \"${MODULE_PATH}/apis/v1beta1\"|clusterv1beta1 \"${MODULE_PATH}/apis/cluster/v1beta1\"|g" \
        -e 's/v1alpha1apis\.SchemeBuilder\.AddToScheme/clusterv1alpha1.SchemeBuilder.AddToScheme/g' \
        -e 's/v1beta1\.SchemeBuilder\.AddToScheme/clusterv1beta1.SchemeBuilder.AddToScheme/g' \
        apis/zz_register.go

    rm -f apis/zz_register.go.tmp
    log_info "  ✓ Fixed apis/zz_register.go"
else
    log_warn "  ⊗ apis/zz_register.go not found (may not be generated yet)"
fi

# Fix 2: Create apis/cluster/register.go
log_info "Fix 2: Creating apis/cluster/register.go..."

mkdir -p apis/cluster
cat > apis/cluster/doc.go <<'EOF'
// Package cluster contains the cluster-scoped API group registration.
package cluster
EOF

cat > apis/cluster/register.go <<EOF
// Package cluster contains the cluster-scoped API group registration.
package cluster

import (
    "k8s.io/apimachinery/pkg/runtime"

    clusterv1alpha1 "${MODULE_PATH}/apis/cluster/v1alpha1"
)

// AddToScheme adds all cluster-scoped APIs to the scheme.
func AddToScheme(s *runtime.Scheme) error {
    if err := clusterv1alpha1.SchemeBuilder.AddToScheme(s); err != nil {
        return err
    }
    // v1beta1 may not exist yet - only add if package is generated
    // clusterv1beta1.SchemeBuilder.AddToScheme(s)
    return nil
}
EOF
log_info "  ✓ Created apis/cluster/{doc.go,register.go}"

# Fix 3: Create apis/namespaced/register.go
log_info "Fix 3: Creating apis/namespaced/register.go..."

mkdir -p apis/namespaced
cat > apis/namespaced/doc.go <<'EOF'
// Package namespaced contains the namespace-scoped API group registration.
package namespaced
EOF

cat > apis/namespaced/register.go <<'EOF'
// Package namespaced contains the namespace-scoped API group registration.
package namespaced

import (
    "k8s.io/apimachinery/pkg/runtime"
)

// AddToScheme adds all namespace-scoped APIs to the scheme.
// AAP provider has only cluster-scoped resources, so this is a no-op.
func AddToScheme(s *runtime.Scheme) error {
    // No namespace-scoped resources for AAP
    return nil
}
EOF
log_info "  ✓ Created apis/namespaced/{doc.go,register.go}"

# Fix 4: Create internal/controller/cluster/setup.go
log_info "Fix 4: Creating internal/controller/cluster/setup.go..."

mkdir -p internal/controller/cluster
cat > internal/controller/cluster/doc.go <<'EOF'
// Package cluster contains the cluster-scoped controller setup.
package cluster
EOF

cat > internal/controller/cluster/setup.go <<EOF
// Package cluster contains the cluster-scoped controller setup.
package cluster

import (
    ctrl "sigs.k8s.io/controller-runtime"

    "github.com/crossplane/upjet/v2/pkg/controller"

    "${MODULE_PATH}/internal/controller/cluster/group"
    "${MODULE_PATH}/internal/controller/cluster/host"
    "${MODULE_PATH}/internal/controller/cluster/inventory"
    "${MODULE_PATH}/internal/controller/cluster/job"
    "${MODULE_PATH}/internal/controller/cluster/providerconfig"
    "${MODULE_PATH}/internal/controller/cluster/workflowjob"
)

// Setup sets up all cluster-scoped controllers.
func Setup(mgr ctrl.Manager, o controller.Options) error {
    for _, setup := range []func(ctrl.Manager, controller.Options) error{
        providerconfig.Setup,
        group.Setup,
        host.Setup,
        inventory.Setup,
        job.Setup,
        workflowjob.Setup,
    } {
        if err := setup(mgr, o); err != nil {
            return err
        }
    }
    return nil
}

// SetupGated sets up all cluster-scoped controllers with gating.
func SetupGated(mgr ctrl.Manager, o controller.Options) error {
    for _, setup := range []func(ctrl.Manager, controller.Options) error{
        providerconfig.SetupGated,
        group.SetupGated,
        host.SetupGated,
        inventory.SetupGated,
        job.SetupGated,
        workflowjob.SetupGated,
    } {
        if err := setup(mgr, o); err != nil {
            return err
        }
    }
    return nil
}
EOF
log_info "  ✓ Created internal/controller/cluster/{doc.go,setup.go}"

# Fix 5: Create internal/controller/namespaced/setup.go
log_info "Fix 5: Creating internal/controller/namespaced/setup.go..."

mkdir -p internal/controller/namespaced
cat > internal/controller/namespaced/doc.go <<'EOF'
// Package namespaced contains the namespace-scoped controller setup.
package namespaced
EOF

cat > internal/controller/namespaced/setup.go <<'EOF'
// Package namespaced contains the namespace-scoped controller setup.
package namespaced

import (
    ctrl "sigs.k8s.io/controller-runtime"

    "github.com/crossplane/upjet/v2/pkg/controller"
)

// Setup sets up all namespace-scoped controllers.
// AAP provider has only cluster-scoped resources, so this is a no-op.
func Setup(mgr ctrl.Manager, o controller.Options) error {
    return nil
}

// SetupGated sets up all namespace-scoped controllers with gating.
// AAP provider has only cluster-scoped resources, so this is a no-op.
func SetupGated(mgr ctrl.Manager, o controller.Options) error {
    return nil
}
EOF
log_info "  ✓ Created internal/controller/namespaced/{doc.go,setup.go}"

# Verify expected imports exist (don't fail, just warn)
log_info "Verifying controller packages exist..."
for pkg in group host inventory job workflowjob; do
    if [[ -d "internal/controller/cluster/$pkg" ]]; then
        log_info "  ✓ internal/controller/cluster/$pkg exists"
    else
        log_warn "  ⊗ internal/controller/cluster/$pkg not found (may be generated later)"
    fi
done

# Run gofmt to clean up formatting
log_info "Running gofmt on generated files..."
gofmt -w apis/cluster/ apis/namespaced/ internal/controller/cluster/ internal/controller/namespaced/ 2>/dev/null || true

log_info ""
log_info "${GREEN}Post-generate fixes completed successfully!${NC}"
log_info ""
log_info "Next steps:"
log_info "  1. Run: make generate     (if not already done)"
log_info "  2. Run: make build        (build provider binary + image)"
log_info "  3. Test: make run         (run provider locally)"
log_info ""
log_info "If 'make generate' was already run and failed, you may need to:"
log_info "  - Fix any compilation errors in internal/controller/cluster/setup.go"
log_info "  - Re-run controller-gen manually (see BUILD.md step 3.4)"
