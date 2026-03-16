#!/usr/bin/env bash
# Apply post-generate fixes in the provider repo after 'make generate'.
# Usage: ./hack/apply-post-generate-fixes.sh <scaffold_repo> <provider_repo>
# - scaffold_repo: path to aap-crossplane (this repo)
# - provider_repo: path to the cloned provider (e.g. provider-aap)
#
# Import paths always follow <module from go.mod>/... so we never hardcode org/repo.
set -euo pipefail

SCAFFOLD_REPO="${1:?scaffold repo path required}"
PROVIDER_REPO="${2:?provider repo path required}"

GO_MOD="${PROVIDER_REPO}/go.mod"
if [[ ! -f "${GO_MOD}" ]]; then
  echo "apply-post-generate-fixes: ERROR: ${GO_MOD} not found" >&2
  exit 1
fi
MODULE=$(grep -E '^module[[:space:]]+' "${GO_MOD}" | head -1 | awk '{print $2}' | tr -d '\r')
if [[ -z "${MODULE}" ]]; then
  echo "apply-post-generate-fixes: ERROR: could not parse module path from ${GO_MOD}" >&2
  exit 1
fi

# Scaffold copies under hack/post-generate-fixes use this default; replace with real module after copy.
DEFAULT_MODULE_IMPORT="${APPLY_POST_GENERATE_DEFAULT_MODULE:-github.com/crossplane-contrib/provider-aap}"

# Fix apis/zz_register.go: point imports at apis/cluster/... and fix SchemeBuilder refs.
# Patterns use ${MODULE} so forks / custom go.mod module paths still match.
ZZ_REGISTER="${PROVIDER_REPO}/apis/zz_register.go"
if [[ -f "${ZZ_REGISTER}" ]]; then
  sed -i.bak \
    -e "s|v1alpha1apis \"${MODULE}/apis/v1alpha1\"|clusterv1alpha1 \"${MODULE}/apis/cluster/v1alpha1\"|" \
    -e "s|v1beta1 \"${MODULE}/apis/v1beta1\"|clusterv1beta1 \"${MODULE}/apis/cluster/v1beta1\"|" \
    -e 's/v1alpha1apis\.SchemeBuilder\.AddToScheme/clusterv1alpha1.SchemeBuilder.AddToScheme/' \
    -e 's/v1beta1\.SchemeBuilder\.AddToScheme/clusterv1beta1.SchemeBuilder.AddToScheme/' \
    "${ZZ_REGISTER}"
  rm -f "${ZZ_REGISTER}.bak"
fi

cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/apis/cluster" "${PROVIDER_REPO}/apis/"
cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/apis/namespaced" "${PROVIDER_REPO}/apis/"
cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/internal/controller/cluster" "${PROVIDER_REPO}/internal/controller/"
cp -r "${SCAFFOLD_REPO}/hack/post-generate-fixes/internal/controller/namespaced" "${PROVIDER_REPO}/internal/controller/"

# Align copied Go files with whatever module path prepare.sh wrote into go.mod.
while IFS= read -r -d '' f; do
  sed -i.bak -e "s|${DEFAULT_MODULE_IMPORT}|${MODULE}|g" "${f}"
  rm -f "${f}.bak"
done < <(find "${PROVIDER_REPO}/apis/cluster" "${PROVIDER_REPO}/apis/namespaced" \
  "${PROVIDER_REPO}/internal/controller/cluster" "${PROVIDER_REPO}/internal/controller/namespaced" \
  -name '*.go' -print0 2>/dev/null || true)

echo "Post-generate fixes applied to ${PROVIDER_REPO} (Go module: ${MODULE})"
