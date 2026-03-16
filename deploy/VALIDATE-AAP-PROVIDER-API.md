# Validate AAP Crossplane provider vs running AAP API

This describes how to check that the AAP Crossplane provider’s managed resources align with the APIs exposed by your running AAP (Ansible Automation Platform) instance.

## Quick run

```bash
kubectl apply -f deploy/validate-aap-provider-api-alignment.yaml
kubectl wait --for=condition=complete job/validate-aap-provider-api -n crossplane-system --timeout=90s
kubectl logs job/validate-aap-provider-api -n crossplane-system
```

Requires: `aap-credentials` secret in `crossplane-system` (token-based). The job mounts the secret and calls the AAP API.

## What is checked

1. **Provider must use api/controller/v2 (not api/v2)** – The job first verifies that `GET $HOST/api/controller/v2/` returns 200. If it does not, the job **fails** with instructions to set the aap-credentials host to include `/api/controller` (e.g. `http://aap-gateway.<ns>.svc.cluster.local/api/controller`). The provider must use the gateway path `/api/controller/v2/`, not the legacy `/api/v2/` path.
2. **AAP API (gateway) controller v2 root** – GET `/api/controller/v2/` and list resource keys returned by the gateway.
3. **Provider-relevant endpoints** – GET each of the following; report HTTP status and (for list endpoints) `count`:
   - `/api/controller/v2/inventories/`
   - `/api/controller/v2/hosts/`
   - `/api/controller/v2/groups/`
   - `/api/controller/v2/jobs/`
   - `/api/controller/v2/workflow_jobs/`
   - `/api/controller/v2/job_templates/`
   - `/api/controller/v2/workflow_job_templates/`
   - `/api/controller/v2/organizations/`
4. **Mapping summary** – Printed at the end: which provider CRDs map to which AAP endpoints, and which AAP resources have no CRD (e.g. job_templates).

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

If an endpoint returns **200** and a `count`, the running AAP instance supports that resource and the provider can call it (for the resources that have CRDs). If an endpoint returns **404** or **401**, note it for your AAP/controller version or auth setup.

## Interpreting results

- **OK** with HTTP 200 and a `count` – Endpoint exists and is usable with the token; provider alignment for that resource is supported.
- **---** with HTTP 404 – Endpoint not found; possible version or path difference (e.g. controller vs gateway path).
- **---** with HTTP 401/403 – Auth or permissions; token may need different scopes or the user may need more access.

AAP 2.5+ uses the gateway; the controller API is at `/api/controller/v2/`. This validation **requires** that path: if `/api/controller/v2/` is not reachable, the job fails. The provider (and aap-credentials `host`) must be configured to use the gateway with `/api/controller` in the base URL so that API calls use `/api/controller/v2/`, not `/api/v2/` only. Older installs may expose `/api/v2/` on the controller; for the gateway, use `/api/controller/v2/`. The job uses gateway service `aap-gateway` by default; adjust the job’s `HOST` or paths if your instance differs.
