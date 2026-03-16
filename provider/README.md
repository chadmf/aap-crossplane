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
