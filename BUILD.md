# Building the AAP Crossplane Provider

This document describes how to create the Crossplane provider for Ansible Automation Platform (AAP) using the **Upjet** approach and the scaffolding in this repo. See [README.md](README.md) for architecture and design.

## Prerequisites

- Go 1.24+ (see upjet-provider-template for current `GO_REQUIRED_VERSION`)
- Terraform 1.5.x (1.6+ uses BSL license; Upjet expects &lt; 1.6)
- Make, git
- Optional: Kind cluster and kubectl for testing

## Step 1: Initialize from Upjet Provider Template

1. Clone the Upjet provider template and set up the build submodule:

   ```bash
   git clone https://github.com/crossplane/upjet-provider-template.git provider-aap
   cd provider-aap
   make submodules
   ```

2. Run the prepare script to rename the template to the AAP provider. Use the values below (or your own org/group):

   ```bash
   # From provider-aap/
   PROVIDER_NAME_LOWER=aap \
   PROVIDER_NAME_NORMAL=AAP \
   ORGANIZATION_NAME=crossplane-contrib \
   CRD_ROOT_GROUP=crossplane.io \
   ./hack/prepare.sh
   ```

   Alternatively, use the helper script from this repo (see [hack/prepare-aap.sh](hack/prepare-aap.sh)).

## Step 2: Apply This Scaffold

From the **aap-crossplane** repo (this repo):

1. Copy provider configuration and AAP-specific Makefile vars into the cloned provider:

   ```bash
   # From aap-crossplane repo root
   PROVIDER_AAP_DIR=/path/to/provider-aap   # your cloned provider-aap directory

   cp -r provider/config/*    $PROVIDER_AAP_DIR/config/
   cp    provider/Makefile.aap $PROVIDER_AAP_DIR/Makefile.aap
   ```

2. Merge Makefile variables: open `$PROVIDER_AAP_DIR/Makefile` and set the Terraform provider block (top of file) to the values in `provider/Makefile.aap`, or `include Makefile.aap` after the project setup section.

3. Remove the template’s sample null resource config (if still present after prepare):

   - Remove or replace `config/cluster/null` and `config/namespaced/null` (or equivalent) so only AAP resources remain in `config/provider.go`.

## Step 3: Configure and Generate

1. **Schema and docs**: From the provider repo, run:

   ```bash
   make generate.init   # Fetches Terraform provider schema and docs
   make generate        # Generates Go APIs and CRDs
   ```

2. If the Terraform AAP provider version or download URL in the Makefile is wrong, fix `TERRAFORM_PROVIDER_VERSION` and `TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX` (and binary name) per [Terraform Registry](https://registry.terraform.io/providers/ansible/aap/latest) and the provider’s [GitHub releases](https://github.com/ansible/terraform-provider-aap/releases).

3. Resolve any config compile errors (e.g. adjust `config/provider.go` imports to match the AAP resource config packages you added). If your provider repo uses a different Go module path than `github.com/crossplane-contrib/provider-aap`, update the imports and `modulePath` in `config/provider.go` accordingly.

## Step 4: Build and Run Locally

```bash
 make build
 make run   # Run provider out-of-cluster (for development)
```

## Step 5: Test in a Cluster

1. Install Crossplane (and the provider) in a Kind cluster.
2. Create a `ProviderConfig` that references a Secret with AAP URL and token (or username/password). See [provider/examples/](provider/examples/).
3. Apply a managed resource (e.g. `Inventory` or `Group`) and verify the resource appears in the AAP UI.

## Scaffold Contents (This Repo)

| Path | Purpose |
|------|--------|
| `provider/Makefile.aap` | Terraform AAP provider Makefile variables. |
| `provider/config/` | Upjet provider config: `provider.go`, `external_name.go`, and per-resource configs for AAP (group, host, inventory, job, workflow_job). |
| `provider/examples/` | Example `ProviderConfig` and sample MR manifests. |
| `hack/prepare-aap.sh` | Default values for `hack/prepare.sh` when initializing the AAP provider from the template. |

## Security Reminders

- **RBAC**: Restrict the provider’s ServiceAccount to the minimum required (secrets and its own CRDs).
- **Credentials**: Prefer AAP Application Tokens scoped to specific Organizations over admin passwords. Store credentials in a Kubernetes Secret referenced by `ProviderConfig`.

## References

- [Upjet: Generating a Provider](https://github.com/crossplane/upjet/blob/main/docs/generating-a-provider.md)
- [upjet-provider-template](https://github.com/crossplane/upjet-provider-template)
- [Terraform Provider: ansible/aap](https://registry.terraform.io/providers/ansible/aap/latest)
- [terraform-provider-aap (GitHub)](https://github.com/ansible/terraform-provider-aap)
