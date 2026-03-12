#!/usr/bin/env bash
# Apply post-generate fixes in the provider repo after 'make generate'.
# Usage: ./hack/apply-post-generate-fixes.sh <scaffold_repo> <provider_repo>
# - scaffold_repo: path to aap-crossplane (this repo)
# - provider_repo: path to the cloned provider (e.g. provider-aap)
set -euo pipefail

SCAFFOLD_REPO="${1:?scaffold repo path required}"
PROVIDER_REPO="${2:?provider repo path required}"

# Fix apis/zz_register.go: use cluster/v1alpha1 and cluster/v1beta1 instead of apis/v1alpha1 and apis/v1beta1
ZZ_REGISTER="${PROVIDER_REPO}/apis/zz_register.go"
if [[ -f "${ZZ_REGISTER}" ]]; then
  sed -i.bak \
    -e 's|v1alpha1apis "github.com/crossplane-contrib/provider-aap/apis/v1alpha1"|clusterv1alpha1 "github.com/crossplane-contrib/provider-aap/apis/cluster/v1alpha1"|' \
    -e 's|v1beta1 "github.com/crossplane-contrib/provider-aap/apis/v1beta1"|clusterv1beta1 "github.com/crossplane-contrib/provider-aap/apis/cluster/v1beta1"|' \
    -e 's/v1alpha1apis\.SchemeBuilder\.AddToScheme/clusterv1alpha1.SchemeBuilder.AddToScheme/' \
    -e 's/v1beta1\.SchemeBuilder\.AddToScheme/clusterv1beta1.SchemeBuilder.AddToScheme/' \
    "${ZZ_REGISTER}"
  rm -f "${ZZ_REGISTER}.bak"
fi

# Copy API and controller fix packages into the provider repo
cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/apis/cluster" "${PROVIDER_REPO}/apis/"
cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/apis/namespaced" "${PROVIDER_REPO}/apis/"
cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/internal/controller/cluster" "${PROVIDER_REPO}/internal/controller/"
cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/internal/controller/namespaced" "${PROVIDER_REPO}/internal/controller/"

echo "Post-generate fixes applied to ${PROVIDER_REPO}"
