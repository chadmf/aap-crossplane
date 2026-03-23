# AAP Crossplane Provider Scaffold

This directory contains the scaffolding used to build the **Crossplane provider for Ansible Automation Platform (AAP)** from the [Upjet provider template](https://github.com/crossplane/upjet-provider-template). It is not a standalone Go module; copy these files into a clone of the template after running `hack/prepare.sh`.

## TL;DR Full build steps

[BUILD.md](../BUILD.md) in the repo root has the instructions to build and deploy the provider.

## Contents

| Path | Description |
|------|-------------|
| **Makefile.aap** | Terraform AAP provider variables. Merge into the provider repo’s main `Makefile`. |
| **config/** | Upjet config: `provider.go`, `external_name.go`, `provider-metadata.yaml`, and per-resource configs under `config/aap/`. |
| **examples/** | Example `ProviderConfig`, Secret, and `Inventory` manifest for testing. |

## Module path in config/provider.go

`config/provider.go` uses the module path `github.com/crossplane-contrib/provider-aap`. If your provider repo uses a different `PROJECT_REPO` (e.g. a different GitHub org), replace that import path in `provider.go` and in the `modulePath` constant so that the `config/aap/*` packages resolve after you copy the scaffold into the provider repo.

## Terraform AAP resources scaffolded

- `aap_group` → Group (CRD kind)
- `aap_host` → Host
- `aap_inventory` → Inventory
- `aap_job` → Job
- `aap_workflow_job` → WorkflowJob

Schema and CRD field details come from the [Terraform provider ansible/aap](https://registry.terraform.io/providers/ansible/aap/latest) when you run `make generate.init` and `make generate` in the provider repo.

## HTTP APIs: controller v2 vs `/api/gateway/v1/`

Managed resources use the **controller** API base from platform discovery (`GET {host}/api/` → `apis.controller` → `current_version`, typically **`/api/controller/v2/`** on AAP 2.5+).

**`/api/gateway/v1/`** is the **platform gateway** REST prefix (e.g. **`/api/gateway/v1/status/`**). It is part of the same gateway host but not the URL prefix Upjet resources use for Inventory/Host/Job CRUD. The Terraform client also discovers **`apis.eda`** for event-driven APIs. See **[AAP-HTTP-APIS.md](./AAP-HTTP-APIS.md)** and **`deploy/testing-scripts/validate-aap-api-suite-job.yaml`** (combined ingress + authenticated checks).
