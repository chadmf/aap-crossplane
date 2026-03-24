# AAP HTTP API surfaces (Crossplane / Terraform ansible/aap)

The embedded [**terraform-provider-aap**](https://github.com/ansible/terraform-provider-aap) client talks to several related HTTP paths on AAP 2.5+. **Credentials `host`** must be the **gateway root** (no `/api/controller` suffix) so **`GET {host}/api/`** succeeds.

## Platform discovery: `GET {host}/api/`

The provider calls **`/api/`** first and parses:

| JSON field | Purpose |
|------------|---------|
| **`apis.controller`** | Relative or absolute URL; the client **GET**s it and reads **`current_version`** → **controller API base** (typically **`/api/controller/v2/`**). |
| **`apis.eda`** | EDA / event-driven API; second hop yields **`current_version`**; path is stored as **`EDAAPIEndpoint`** (used by EDA datasources/actions in Terraform). |

Crossplane managed resources generated today map to **controller** APIs only (`aap_inventory`, `aap_host`, `aap_group`, `aap_job`, `aap_workflow_job`).

## Controller API (`/api/controller/v2/` on AAP 2.5+)

CRUD for inventories, hosts, groups, jobs, etc. Resource code uses `path.Join(getAPIEndpoint(), "inventories")`, etc., where **`getAPIEndpoint()`** is the discovered **`current_version`** string.

## Platform gateway REST v1: `/api/gateway/v1/`

AAP exposes platform gateway endpoints under **`/api/gateway/v1/`** (e.g. **`/api/gateway/v1/status/`** for health). These are **not** the same URL prefix as controller v2, but they share the same **TLS + Route/Service host** as the gateway root.

- Useful for **readiness checks** from inside the cluster (see `deploy/testing-scripts/validate-aap-api-suite-job.yaml` phase 1 and phase 2).
- **EDA** traffic may be routed via gateway paths depending on install; the Terraform client’s **`getEdaAPIEndpoint()`** reflects **`apis.eda`** discovery, not a hardcoded string.

## Adding new Crossplane resources for gateway v1

There is **no** separate Terraform **resource** type for arbitrary `/api/gateway/v1/*` today — only controller resources, EDA **datasources**, and **actions** in upstream Terraform. To expose gateway v1 objects as managed resources you would need:

1. New resources upstream in **ansible/terraform-provider-aap**, then  
2. **`make generate`** in the Upjet provider repo and new entries under `provider/config/aap/` and **`external_name.go`**.

Until then, validate gateway reachability with the Jobs in **`deploy/testing-scripts/`** and use this doc for architecture reference.
