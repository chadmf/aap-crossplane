# GitHub Actions Workflows

This document describes the CI workflows in this repository. Workflow definitions live in [.github/workflows/](.github/workflows/).

## Overview

| Workflow file | Purpose |
|---------------|---------|
| [ci.yml](.github/workflows/ci.yml) | **CI** — Validates scaffold assets and builds the AAP Crossplane provider from the Upjet template + this scaffold. |

## Triggers

- **Push** to `main` or `master`
- **Pull request** targeting `main` or `master`

## CI workflow (ci.yml)

The workflow runs two jobs in parallel: **Validate** (scaffold-only checks) and **Build provider** (full provider build from template + scaffold).

### Job: Validate

Runs on `ubuntu-latest`. Validates assets in this repo only; no provider clone.

| Step | What it does |
|------|----------------|
| Checkout | Check out this repo (aap-crossplane). |
| ShellCheck | Install [ShellCheck](https://www.shellcheck.net/) and lint shell scripts under `hack/` (direct children only, e.g. `hack/prepare-aap.sh`, `hack/apply-post-generate-fixes.sh`). |
| Set up Python | Use Python 3.12. |
| Install yamllint | Install [yamllint](https://yamllint.readthedocs.io/). |
| Validate YAML | Run `yamllint -d relaxed` on `provider/config` and `provider/examples`. |
| Set up Node.js | Use Node.js 20. |
| Install markdownlint-cli | Install [markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli). |
| Lint Markdown | Run markdownlint on `README.md`, `BUILD.md`, and `provider/README.md`. Runs with `continue-on-error: true`. |

### Job: Build provider

Runs on `ubuntu-latest`. Clones the Upjet provider template, applies this scaffold, generates code, applies post-generate fixes, then builds and tests the provider. Mirrors the steps in [BUILD.md](BUILD.md).

| Step | What it does |
|------|----------------|
| Checkout scaffold | Check out this repo (aap-crossplane). |
| Set up Go | Use Go 1.24. |
| Install goimports | Install `golang.org/x/tools/cmd/goimports` and add `$(go env GOPATH)/bin` to `PATH` for later steps. |
| Clone Upjet provider template | Clone [upjet-provider-template](https://github.com/crossplane/upjet-provider-template) into `provider-aap`, then run `make submodules`. |
| Prepare AAP provider | In `provider-aap`, run `hack/prepare.sh` with AAP naming: `PROVIDER_NAME_LOWER=aap`, `PROVIDER_NAME_NORMAL=AAP`, `ORGANIZATION_NAME=crossplane-contrib`, `CRD_ROOT_GROUP=crossplane.io`. |
| Apply scaffold | Copy `provider/config/*` and `provider/Makefile.aap` from this repo into `provider-aap`. Patch the provider `Makefile` to add `-include Makefile.aap` after the `TERRAFORM_VERSION_VALID` block (so the AAP Terraform provider is used instead of the template default). |
| Generate schema and code | In provider-aap: run make generate.init (fetch Terraform schema and docs), then make generate (Upjet codegen). The generate step may fail because it often stops at controller-gen when apis/zz_register.go still references non-existent packages; the pipeline handles this with post-generate fixes. |
| Apply post-generate fixes | Run [hack/apply-post-generate-fixes.sh](hack/apply-post-generate-fixes.sh) with this repo and `provider-aap` as arguments. This patches `apis/zz_register.go` to use `apis/cluster/v1alpha1` and `apis/cluster/v1beta1`, and copies the API and controller fix packages from [hack/post-generate-fixes/](hack/post-generate-fixes/) into the provider repo. |
| Run controller-gen and angryjet | In `provider-aap`: run controller-gen (CRDs) and angryjet (method sets) so generation is complete. |
| Build provider | In `provider-aap`: run `make build` (Go binary and container image). |
| Test | In `provider-aap`: run `make test`. Uses `continue-on-error: true`. |

### Scripts and assets used by the build job

- **[hack/apply-post-generate-fixes.sh](hack/apply-post-generate-fixes.sh)** — Patches `apis/zz_register.go` and copies API/controller packages from `hack/post-generate-fixes/` into the provider repo. See [BUILD.md § Post-generate fixes](BUILD.md#step-3-details-post-generate-fixes).
- **[hack/post-generate-fixes/](hack/post-generate-fixes/)** — Contains the `apis/cluster`, `apis/namespaced`, and `internal/controller/cluster`, `internal/controller/namespaced` packages (e.g. `register.go`, `setup.go`) that the Upjet pipeline does not generate and that the provider’s `main` expects.

## Running locally

- To run the same validation as the **Validate** job (assuming tools are installed):
  - `shellcheck hack/*.sh`
  - `yamllint -d relaxed provider/config provider/examples`
  - `markdownlint README.md BUILD.md provider/README.md`
- To reproduce the **Build provider** job, follow [BUILD.md](BUILD.md) and use [hack/apply-post-generate-fixes.sh](hack/apply-post-generate-fixes.sh) after `make generate` as described there.
