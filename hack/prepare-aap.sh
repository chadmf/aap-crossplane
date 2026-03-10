#!/usr/bin/env bash
# Default values for running upjet-provider-template's hack/prepare.sh
# to create the AAP Crossplane provider.
# Run this from the cloned upjet-provider-template directory, or source it
# and then run ./hack/prepare.sh from that directory.
set -euo pipefail

export PROVIDER_NAME_LOWER="${PROVIDER_NAME_LOWER:-aap}"
export PROVIDER_NAME_NORMAL="${PROVIDER_NAME_NORMAL:-AAP}"
export ORGANIZATION_NAME="${ORGANIZATION_NAME:-crossplane-contrib}"
export CRD_ROOT_GROUP="${CRD_ROOT_GROUP:-crossplane.io}"

echo "Using: PROVIDER_NAME_LOWER=$PROVIDER_NAME_LOWER PROVIDER_NAME_NORMAL=$PROVIDER_NAME_NORMAL ORGANIZATION_NAME=$ORGANIZATION_NAME CRD_ROOT_GROUP=$CRD_ROOT_GROUP"
echo "Run from provider repo: ./hack/prepare.sh"
