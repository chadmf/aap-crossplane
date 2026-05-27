# Crossplane + AAP Integration Architecture

## High-Level Architecture

```mermaid
flowchart TB
  subgraph cluster["OpenShift / Kubernetes cluster"]
    subgraph xp["crossplane-system"]
      XP["Crossplane Core<br/>Package manager · CRDs · RBAC"]
      Prov["AAP Provider (Upjet)<br/>Reconciler · TF state in Secret · AAP client"]
      PC["ProviderConfig (default)<br/>gateway root URL · secret ref"]
      Sec["Secret: aap-credentials<br/>JSON key credentials: host, token"]
      XP --> Prov
      PC --> Prov
      Sec --> Prov
    end

    subgraph user["User namespace (e.g. default)"]
      MR["Managed resources<br/>Inventory · Host · Group · Job · WorkflowJob"]
    end

    subgraph aap["AAP namespace"]
      Op["AAP Operator"]
      Ctrl["AAP Controller<br/>Gateway discovery · Controller v2 · PostgreSQL"]
      Op --> Ctrl
    end

    MR -->|"reconcile"| Prov
    Prov -->|"HTTPS in-cluster or route"| Ctrl
  end
```

| Layer | Responsibility |
| --- | --- |
| **Crossplane Core** | Installs provider package, manages CRDs and RBAC |
| **AAP Provider** | Reconciles managed resources via Terraform/ansible-aap (Upjet) |
| **ProviderConfig + Secret** | Gateway root URL and auth (token or username/password) |
| **Managed resources** | Desired state for AAP objects (inventory, host, group, job, …) |
| **AAP Controller** | Source of truth for AAP API state |

## Reconciliation Flow

```mermaid
sequenceDiagram
  actor User
  participant MR as Managed resource (CR)
  participant R as AAP provider reconciler
  participant API as AAP Controller API v2

  User->>MR: kubectl apply (e.g. Inventory)
  R->>MR: watch / queue
  R->>API: GET …/inventories/ (observe)
  alt resource missing
    R->>API: POST …/inventories/ (create)
  end
  R->>MR: status: Ready, Synced, external-name
  User->>MR: kubectl get inventory

  loop continuous reconcile
    R->>API: GET (observe)
    opt spec differs from AAP
      R->>API: PATCH (update)
    end
  end

  User->>MR: kubectl delete
  R->>API: DELETE …/inventories/{id}
  R->>MR: remove finalizer → CR gone
```

Example after create:

```text
NAME               READY   SYNCED   EXTERNAL-NAME
example-inventory  True    True     5
```

## Component Details

### 1. Crossplane Core

- Package manager for providers
- CRD lifecycle management
- RBAC and security
- Provider health monitoring

### 2. AAP Provider (Upjet-based)

- Built with Crossplane Upjet
- Wraps Terraform provider [ansible/aap](https://registry.terraform.io/providers/ansible/aap)
- Stores Terraform state in Kubernetes Secrets
- Reconciler loop: **Observe** (GET) → **Create** (POST) → **Update** (PATCH on drift) → **Delete** (DELETE)

### 3. Managed Resources

| CRD | API group | AAP endpoint (under discovered controller base) |
| --- | --- | --- |
| `Inventory` | `aap.aap.crossplane.io` | `/api/controller/v2/inventories/` |
| `Host` | `aap.aap.crossplane.io` | `/api/controller/v2/hosts/` |
| `Group` | `aap.aap.crossplane.io` | `/api/controller/v2/groups/` |
| `Job` | `job.aap.crossplane.io` | `/api/controller/v2/jobs/` |
| `WorkflowJob` | `workflowjob.aap.crossplane.io` | `/api/controller/v2/workflow_jobs/` |

Future: `JobTemplate`, `WorkflowJobTemplate`, `Project`, `Organization`. See [VALIDATE-AAP-PROVIDER-API.md](deploy/VALIDATE-AAP-PROVIDER-API.md) for the full mapping.

### 4. ProviderConfig

- `apiVersion: aap.crossplane.io/v1beta1`
- References Secret `aap-credentials` in `crossplane-system` (key `credentials`)
- `host` must be the **gateway root** (no `/api/controller` suffix)
- Auth: OAuth2/application token (recommended) or username/password

### 5. AAP Controller

- Deployed via AAP Operator (`AnsibleAutomationPlatform` CR on 2.6+)
- Discovery: `GET {gateway_root}/api/` → controller base → v2 CRUD
- PostgreSQL backend for platform state
- In-cluster: `http://<route-or-service>.<namespace>.svc`
- External: cluster Route/Ingress (e.g. `https://aap.example.com`)

## Key Concepts

### State vs. Action

- **Crossplane manages state**: “This inventory should exist with these properties.”
- **Ansible performs actions**: “Run this playbook now.”
- **Pattern**: configuration CRDs (e.g. future `JobTemplate`) vs. execution CRDs (`Job`, `WorkflowJob`). See [ADR-002-job-crd-semantics.md](adr/ADR-002-job-crd-semantics.md).

### Drift Detection

1. Observe current state in AAP (GET)
2. Compare with desired state (CR `spec`)
3. PATCH AAP if drift detected
4. Update CR `status`

### Security

- Provider ServiceAccount uses minimal RBAC
- Credentials only in Kubernetes Secrets
- Prefer scoped application tokens over admin passwords
- Provider → AAP traffic stays in-cluster when using Service DNS

## Data Flow (Inventory example)

```mermaid
flowchart TD
  A[User applies Inventory CR] --> B[Crossplane queues reconcile]
  B --> C[Provider reads ProviderConfig + Secret]
  C --> D["GET …/inventories/?name=…"]
  D --> E{Exists?}
  E -->|No| F["POST …/inventories/"]
  E -->|Yes| G[Compare spec vs AAP]
  F --> H[AAP returns id e.g. 5]
  G --> H
  H --> I["status: Ready, Synced, external-name: 5"]
  I --> J[kubectl get inventory]
```

## Future Enhancements

1. **JobTemplate / WorkflowJobTemplate** — declare templates via Crossplane
2. **Project / Organization** — broader platform scope
3. **Composition** — higher-level abstractions (e.g. application stack)
4. **Cross-namespace references** — inventory in one namespace, hosts in another
