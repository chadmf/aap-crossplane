# Building the AAP Crossplane Provider

This document describes how to create the Crossplane provider for Ansible Automation Platform (AAP) using the **Upjet** approach and the scaffolding in this repo. See [README.md](README.md) for architecture and design.

## Prerequisites

- Go 1.24+ (see upjet-provider-template for current `GO_REQUIRED_VERSION`)
- Terraform 1.5.x (1.6+ uses BSL license; Upjet expects &lt; 1.6)
- Make, git
- **goimports** (required for `make generate`): `go install golang.org/x/tools/cmd/goimports@latest` and ensure `$(go env GOPATH)/bin` is on your `PATH`
- Optional: Kind cluster and kubectl for testing

## Step 1: Initialize from Upjet Provider Template

1. Clone the Upjet provider template and set up the build submodule:

   ```bash
   git clone https://github.com/crossplane/upjet-provider-template.git provider-aap
   cd provider-aap
   make submodules
   PROVIDER_AAP_DIR=$PWD
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

1. Copy provider configuration and AAP-specific Makefile vars into the cloned provider. Set `PROVIDER_AAP_DIR` to the path of your cloned provider repo (e.g. `export PROVIDER_AAP_DIR=/path/to/provider-aap`). From a clone of this repo:

   ```bash
   git clone https://github.com/chadmf/aap-crossplane.git
   cd aap-crossplane
   cp -r provider/config/*    $PROVIDER_AAP_DIR/config/
   cp    provider/Makefile.aap $PROVIDER_AAP_DIR/Makefile.aap
   ```

2. **Merge the AAP Makefile into the provider**: In `$PROVIDER_AAP_DIR/Makefile`, after the `TERRAFORM_VERSION_VALID` block and before the `export TERRAFORM_PROVIDER_SOURCE` line, add:

   ```makefile
   # AAP Terraform provider (override template defaults)
   -include Makefile.aap
   ```

   This ensures the provider uses the Terraform `ansible/aap` provider instead of the template’s default `hashicorp/null`.

3. **Terraform provider version**: The scaffold uses **Terraform provider version 1.4.0** (not 0.4.0). The [Terraform Registry](https://registry.terraform.io/providers/ansible/aap/latest) and [GitHub releases](https://github.com/ansible/terraform-provider-aap/releases) publish 1.x; 0.4.0 is not available. Both `aap-crossplane/Makefile.aap` and the provider’s `Makefile.aap` should have `TERRAFORM_PROVIDER_VERSION ?= 1.4.0`.

## Step 3: Configure and Generate

1. **Schema and docs** (from the provider repo, with `goimports` on `PATH`):

   ```bash
   export PATH="$(go env GOPATH)/bin:$PATH"   # if goimports is in GOPATH/bin
   cd $PROVIDER_AAP_DIR
   make generate.init   # Fetches Terraform provider schema and docs for ansible/aap
   make generate        # Generates Go APIs and CRDs
   ```

2. **If `make generate` fails or you re-run it**, apply the following post-generate fixes in the **provider repo** (see [Step 3 details: post-generate fixes](#step-3-details-post-generate-fixes) below).

3. If the Terraform AAP provider version or download URL is wrong, adjust `TERRAFORM_PROVIDER_VERSION` and `TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX` (and binary name) per the [Terraform Registry](https://registry.terraform.io/providers/ansible/aap/latest) and [GitHub releases](https://github.com/ansible/terraform-provider-aap/releases).

4. If your provider repo uses a different Go module path than `github.com/crossplane-contrib/provider-aap`, update the imports and `modulePath` in `config/provider.go` accordingly.

### Step 3 details: Provider config (this repo)

- **`config/provider.go`** must define **`GetProviderNamespaced()`** in addition to `GetProvider()`. The template’s generator and main expect both. For AAP, all resources are cluster-scoped; implement `GetProviderNamespaced()` to return `nil` so only cluster-scoped resources are generated and the namespaced controller is effectively no-op when given a nil provider.

### Step 3 details: Post-generate fixes

After the first successful `make generate` (or if you run it again), the Upjet pipeline may generate code that expects packages which are laid out differently in the template. Apply these fixes in the **provider repo** (`$PROVIDER_AAP_DIR`):

1. **`apis/zz_register.go`**  
   The generator may import `apis/v1alpha1` and `apis/v1beta1`, which do not exist; the actual packages are `apis/cluster/v1alpha1` and `apis/cluster/v1beta1`. Change the imports and `AddToSchemes` to use the cluster packages, for example:

   - `v1alpha1apis "github.com/.../apis/v1alpha1"` → `clusterv1alpha1 "github.com/.../apis/cluster/v1alpha1"`
   - `v1beta1 "github.com/.../apis/v1beta1"` → `clusterv1beta1 "github.com/.../apis/cluster/v1beta1"`
   - In `init()`, use `clusterv1alpha1.SchemeBuilder.AddToScheme` and `clusterv1beta1.SchemeBuilder.AddToScheme`.

2. **API register packages**  
   The main binary expects `apis/cluster` and `apis/namespaced` to exist and to expose `AddToScheme(s *runtime.Scheme) error`:

   - **`apis/cluster/doc.go`**: `package cluster`.
   - **`apis/cluster/register.go`**: Implement `AddToScheme` by adding `cluster/v1alpha1` and `cluster/v1beta1` to the given scheme (call their `SchemeBuilder.AddToScheme(s)`).
   - **`apis/namespaced/doc.go`**: `package namespaced`.
   - **`apis/namespaced/register.go`**: Implement `AddToScheme` by adding `namespaced/v1alpha1` and `namespaced/v1beta1` to the given scheme.

3. **Controller setup packages**  
   The main binary expects `internal/controller/cluster` and `internal/controller/namespaced` to expose `Setup(mgr, o)` and `SetupGated(mgr, o)`:

   - **`internal/controller/cluster/doc.go`**: `package cluster`.
   - **`internal/controller/cluster/setup.go`**: `Setup` and `SetupGated` that call `cluster/providerconfig.Setup` and `cluster/providerconfig.SetupGated`.
   - **`internal/controller/namespaced/doc.go`**: `package namespaced`.
   - **`internal/controller/namespaced/setup.go`**: `Setup` and `SetupGated` that call `namespaced/providerconfig.Setup` and `namespaced/providerconfig.SetupGated`.

4. **If `make generate` fails at controller-gen** (e.g. missing `apis/v1alpha1`), fix `zz_register.go` as in (1), then run the remaining steps manually from the provider repo root:

   ```bash
   go run -tags generate sigs.k8s.io/controller-tools/cmd/controller-gen object:headerFile=./hack/boilerplate.go.txt paths=./apis/... crd:allowDangerousTypes=true,crdVersions=v1 output:artifacts:config=./package/crds
   go run -tags generate github.com/crossplane/crossplane-tools/cmd/angryjet generate-methodsets --header-file=./hack/boilerplate.go.txt ./apis/...
   ```

   This avoids re-running the full `make generate` (which would delete and regenerate `zz_register.go` and overwrite the import fix).

## Step 4: Build and Run Locally

- **Go build**: The provider binary builds with the Makefile’s Go build step. If `make build` fails with `docker: command not found`, the image build is optional; the binary has already been built.
- **Run locally** (no Docker required):

  ```bash
  make run   # Run provider out-of-cluster (development)
  ```

- **Full build** (binary + container image): Run `make build` when Docker is installed and on `PATH` if you need the provider image.

## Step 5: Test in a Cluster

1. Install Crossplane (and the provider) in a Kind cluster.
2. Create a `ProviderConfig` that references a Secret with AAP URL and token (or username/password). See [provider/examples/](provider/examples/).
3. Apply a managed resource (e.g. `Inventory` or `Group`) and verify the resource appears in the AAP UI.

## Scaffold Contents (This Repo)

| Path | Purpose |
|------|--------|
| `provider/Makefile.aap` | Terraform AAP provider Makefile variables (use version 1.4.0). |
| `provider/config/` | Upjet provider config: `provider.go` (includes `GetProvider()` and `GetProviderNamespaced()` returning `nil`), `external_name.go`, and per-resource configs for AAP (group, host, inventory, job, workflow_job). |
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
