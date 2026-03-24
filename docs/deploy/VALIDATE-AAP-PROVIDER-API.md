# Validate AAP Crossplane provider vs running AAP API

This describes how to check that the AAP Crossplane provider's managed resources align with the APIs exposed by your running AAP (Ansible Automation Platform) instance.

## Quick run

```bash
kubectl apply -f deploy/testing-scripts/validate-aap-api-suite-job.yaml
kubectl wait --for=condition=complete job/validate-aap-api-suite -n crossplane-system --timeout=300s
kubectl logs job/validate-aap-api-suite -n crossplane-system
```

The suite Job runs **ingress checks** (phase 1) and **authenticated** checks (phase 2) when `aap-credentials` is mounted. For alignment-only from a cluster without CRC ingress, set **`AAP_SKIP_INGRESS_CHECKS=1`** on the Job env.

Requires: `aap-credentials` secret in `crossplane-system` (token-based). The job mounts the secret and calls the AAP API.

## What is checked

1. **Same discovery as Terraform ansible/aap** – The job runs the provider’s discovery sequence: `GET $GATEWAY_ROOT/api/` (must be 200), then follows `apis.controller`, then reads `current_version`. That value is the **same API base** the Crossplane provider uses for CRUD (equivalent to reaching **`/api/controller/v2/`** on AAP 2.5+ gateway). Credentials **`host`** must be the **gateway root** with **no** `/api/controller` suffix (otherwise the provider would call `.../api/controller/api/` and fail).
2. **Controller v2 root** – GET `{API_BASE}/` and list resource keys (inventories, hosts, jobs, …).
3. **Provider-relevant endpoints** – GET each path **under the discovered base**; report HTTP status and (for list endpoints) `count`:
   - `/api/controller/v2/inventories/`
   - `/api/controller/v2/hosts/`
   - `/api/controller/v2/groups/`
   - `/api/controller/v2/jobs/`
   - `/api/controller/v2/workflow_jobs/`
   - `/api/controller/v2/job_templates/`
   - `/api/controller/v2/workflow_job_templates/`
   - `/api/controller/v2/organizations/`
4. **Platform `/api/gateway/v1/`** – The job GETs **`{gateway_root}/api/gateway/v1/status/`** and **`/api/gateway/v1/`** (same **`host`** as credentials; different path prefix than controller v2). See [provider/AAP-HTTP-APIS.md](../../provider/AAP-HTTP-APIS.md).
5. **`apis.eda`** – If present in **`GET /api/`**, shows the EDA discovery link (Terraform **`getEdaAPIEndpoint()`**).
6. **Mapping summary** – Printed at the end: which provider CRDs map to which AAP endpoints, and which AAP resources have no CRD (e.g. job_templates).

## Provider ↔ AAP API mapping

| Provider CRD (Crossplane)        | AAP API endpoint (via gateway) | Notes                          |
|----------------------------------|-------------------------------|--------------------------------|
| `Inventory` (aap.aap.crossplane.io) | `/api/controller/v2/inventories/` | Create/update/delete inventories |
| `Host` (aap.aap.crossplane.io)   | `/api/controller/v2/hosts/`   | Create/update/delete hosts      |
| `Group` (aap.aap.crossplane.io)  | `/api/controller/v2/groups/` | Create/update/delete groups    |
| `Job` (job.aap.crossplane.io)    | `/api/controller/v2/jobs/`    | Launch job from template        |
| `WorkflowJob` (job.aap.crossplane.io) | `/api/controller/v2/workflow_jobs/` | Launch workflow job   |
| *(no CRD)*                       | `/api/controller/v2/job_templates/` | Create via UI/API only     |
| *(no CRD)*                       | `/api/controller/v2/workflow_job_templates/` | Create via UI/API only |
| *(no CRD)*                       | `/api/controller/v2/organizations/` | Typically pre-existing   |
| *(no MR today)*                  | `/api/gateway/v1/*`            | Platform gateway REST v1; separate from controller CRUD — [provider/AAP-HTTP-APIS.md](../../provider/AAP-HTTP-APIS.md) |

If an endpoint returns **200** and a `count`, the running AAP instance supports that resource and the provider can call it (for the resources that have CRDs). If an endpoint returns **404** or **401**, note it for your AAP/controller version or auth setup.

## Interpreting results

- **OK** with HTTP 200 and a `count` – Endpoint exists and is usable with the token; provider alignment for that resource is supported.
- **---** with HTTP 404 – Endpoint not found; possible version or path difference (e.g. controller vs gateway path).
- **---** with HTTP 401/403 – Auth or permissions; token may need different scopes or the user may need more access.

AAP 2.5+ uses the **gateway** (Route or in-cluster entry Service); the controller **Service** (`aap-controller-service`) is deprecated. The controller **API** resolves to **`/api/controller/v2/`** via platform discovery. On **CRC**, nip.io app hostnames resolve to **127.0.0.1** from Pods; [validate-aap-api-suite-job.yaml](../../deploy/testing-scripts/validate-aap-api-suite-job.yaml) phase 1 uses **internal ingress** + **`Host:`**. For **`aap-credentials`**, set `host` to the **gateway root** reachable from the provider Pod, e.g. **`http://aap.<ns>.svc.cluster.local`** (no path suffix), not the nip.io URL.
