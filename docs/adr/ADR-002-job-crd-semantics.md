# ADR-002: Job CRD as Action Trigger, Not State Resource

## Status

**Accepted** (2026-03-31)

## Context

The AAP Crossplane provider faces a fundamental architectural mismatch between Crossplane's state-based provisioning model and Ansible Automation Platform's action-based execution model:

- **Crossplane's model**: Declarative state provisioning ("This resource should exist with these properties")
- **AAP's model**: Imperative action execution ("Run this playbook now with these parameters")

The `aap_job` Terraform resource and corresponding Crossplane `Job` CRD represent **job execution/launch**, not a stateful resource like Inventory or Host. Key questions that must be answered:

1. **Deletion semantics**: What happens when a `Job` CR is deleted?
   - Should it cancel/delete the running job in AAP?
   - Should it do nothing (orphan the job)?
   - Should it be configurable per CR?

2. **Idempotency**: How do we prevent unintended re-runs?
   - Creating the same `Job` CR twice - should it launch twice?
   - What triggers a new job execution vs reconciling existing state?

3. **Failure handling**: How should failures be handled?
   - What retry logic applies?
   - How do we distinguish between "job failed" vs "couldn't launch job"?
   - What backoff strategy prevents overwhelming AAP?

4. **Lifecycle mismatch**: AAP jobs have finite lifecycles (pending → running → completed/failed/canceled), while Crossplane expects resources to persist indefinitely.

## Decision

### 1. Deletion Policy: **Orphan** (default and recommended)

The `Job` CRD uses `deletionPolicy: Orphan` as the default and recommended approach:

```yaml
spec:
  deletionPolicy: Orphan  # Deleting CR does not affect job in AAP
```

**Rationale**:
- AAP jobs are audit records - deleting them destroys observability
- Job execution is atomic and time-bounded - once launched, AAP owns the lifecycle
- Canceling jobs has operational risk (partial infrastructure changes)
- Teams may want to delete CRs for cleanup without affecting running automation

**Alternative considered**: `deletionPolicy: Delete` could cancel running jobs, but:
- Creates risk of accidentally canceling critical automation
- Terraform provider behavior unclear (may not support cancel API)
- Crossplane deletion is often used for namespace cleanup, not operational intent

### 2. Idempotency: **Trigger-based Re-run**

Jobs are re-launched only when the `triggers` field changes:

```yaml
spec:
  forProvider:
    jobTemplateId: 7
    triggers:
      launched_at: "2026-03-31T10:00:00Z"  # Change this to re-run
```

**Rationale**:
- Explicit user intent required for re-runs
- Prevents drift reconciliation from launching duplicate jobs
- Aligns with Terraform's null_resource trigger pattern
- Immutable audit trail (different trigger value = different job instance)

**Consequences**:
- Users must manually update `triggers` to re-launch
- No automatic retry on job failure (requires external controller)
- Drift in AAP (e.g., manually deleting job) won't cause reconciliation re-run

### 3. Failure Handling: **Fail Fast, Manual Retry**

Job CR reconciliation failures (cannot launch job) are surfaced immediately as status conditions:

```yaml
status:
  conditions:
  - type: Ready
    status: False
    reason: LaunchFailed
    message: "AAP API returned 404: job template not found"
```

**Rationale**:
- Terraform provider (and thus Upjet) has no retry logic for execution resources
- AAP job failures (playbook errors) are separate from launch failures
- Automated retries could mask configuration issues (wrong template ID, auth failures)

**Consequences**:
- Operators must monitor CR status and manually fix/retry failed launches
- No built-in circuit breaker or backoff (relies on Crossplane reconciliation limits)
- Job execution failures (inside AAP) are visible only via AAP UI/API, not CR status

### 4. Job as Launch Record, Not Job Template

The `Job` CRD represents **a single job execution**, not the reusable template:

- **Job Template** (config): Created in AAP (UI/API/automation), referenced by ID
- **Job** (execution): Created as Crossplane CR, launches a run of the template

**Rationale**:
- Aligns with AAP's domain model (templates are config, jobs are executions)
- Terraform provider does not expose job_template resource (as of 1.4.0)
- Separation allows managing templates independently from runs

**Consequences**:
- Job templates must be pre-created (out-of-band from Crossplane)
- Non-declarative workflow for template creation
- Future ADR may define `JobTemplate` CRD when upstream support exists

## Consequences

### What Becomes Easier

1. **Audit trail preservation**: Deleting CRs doesn't destroy AAP execution history
2. **Safe cleanup**: Namespaces can be deleted without operational impact
3. **Explicit re-runs**: Trigger changes make intent clear
4. **Separation of concerns**: Template config vs job execution are distinct

### What Becomes Harder

1. **No automatic retry**: Failed launches require manual intervention
2. **No job cancellation**: Deleting CR doesn't stop running jobs (requires AAP API/UI)
3. **Template management gap**: Job templates must be created outside Crossplane
4. **Status visibility**: Job execution status (playbook errors) not reflected in CR status

### Operational Impact

**For platform teams**:
- Must establish separate workflow for job template provisioning
- Need external monitoring for job execution status (AAP UI, metrics)
- CR lifecycle (create/delete) is safe and doesn't affect running automation

**For developers**:
- Launching jobs is declarative (apply YAML)
- Re-running requires updating `triggers` field
- Failures require checking CR status conditions + AAP logs

## Trade-offs

| Approach | Gained | Given Up |
|----------|--------|----------|
| **Orphan deletion** | Safety, audit trail | Direct job cancellation |
| **Trigger-based re-run** | Explicit intent, audit | Automatic retry, drift correction |
| **Fail fast** | Clear error visibility | Resilience to transient failures |
| **Separate Job/Template** | Domain clarity | Unified declarative workflow |

## Review Criteria

This ADR should be reviewed when:

1. **Terraform provider adds job_template resource** → May enable full declarative workflow
2. **Crossplane gains action-resource patterns** → May provide better lifecycle primitives
3. **Users report frequent launch failures** → May need retry/backoff logic
4. **Job cancellation becomes critical** → May need Delete policy option

Review date: **2026-09-30** (6 months)

## Related Decisions

- **ADR-001** (pending): Upjet vs Native Go Provider - affects customization options
- **Future ADR**: JobTemplate CRD semantics when upstream support exists
- **Future ADR**: WorkflowJob semantics (similar concerns, more complex dependencies)

## References

- Crossplane deletion policies: https://docs.crossplane.io/latest/concepts/managed-resources/#deletionpolicy
- Terraform null_resource triggers: https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource#triggers
- AAP Job API: https://docs.ansible.com/automation-controller/latest/html/controllerapi/api_ref.html#/Jobs
- Example Job CR: [examples/example-job.yaml](../../examples/example-job.yaml)
