# Upstream Feature Requests

This directory contains detailed feature request specifications for missing resources in the [Terraform ansible/aap provider](https://github.com/ansible/terraform-provider-aap).

## Purpose

The AAP Crossplane provider uses [Upjet](https://github.com/crossplane/upjet) to wrap the Terraform ansible/aap provider. Resources not available in the Terraform provider cannot be included in the Crossplane provider.

These documents serve as:
1. **Templates** for filing upstream issues
2. **Specifications** for what we need from each resource
3. **Tracking** of blockers preventing full declarative AAP management

## Priority Blockers

| Resource | Priority | Status | Upstream Issue |
|----------|----------|--------|----------------|
| [JobTemplate](job-template-request.md) | 🔴 Critical | Blocked | [File Issue](https://github.com/ansible/terraform-provider-aap/issues/new) |
| [Project](project-request.md) | 🟠 High | Blocked | [File Issue](https://github.com/ansible/terraform-provider-aap/issues/new) |
| Organization | 🟡 Medium | Blocked | TBD |
| Credential | 🟡 Medium | Blocked | TBD |
| ExecutionEnvironment | 🟢 Low | Blocked | TBD |

## How to Use

### Filing an Upstream Request

1. **Read the request document** for the resource (e.g., `job-template-request.md`)
2. **Copy the "Upstream Issue Template" section** from the document
3. **File an issue** at https://github.com/ansible/terraform-provider-aap/issues/new
4. **Create a tracking issue** in aap-crossplane using the [upstream-request template](../../.github/ISSUE_TEMPLATE/upstream-request.md)
5. **Link the two issues** (upstream issue → tracking issue)
6. **Engage in discussion** - answer questions, provide use cases

### Tracking Progress

Update the tracking issue as progress is made:
- Upstream issue filed → Label: `upstream-filed`
- Under discussion → Label: `upstream-discussion`
- Accepted/planned → Label: `upstream-accepted`
- Implemented upstream → Label: `upstream-merged`
- Available in release → Label: `upstream-released`
- Integrated into aap-crossplane → Close tracking issue

## Resource Specifications

### JobTemplate (Critical)

**What it does**: Defines a reusable automation job (playbook + inventory + credentials + settings)

**Why critical**: Job Templates are the core automation unit in AAP. Without this resource, teams cannot define complete automation workflows declaratively.

**Workaround**: Manually create templates in AAP UI, reference by ID in Job CRs (breaks GitOps)

**Specification**: [job-template-request.md](job-template-request.md)

### Project (High)

**What it does**: References a Git repository containing Ansible playbooks

**Why high**: Projects are required by Job Templates. Cannot create JobTemplates declaratively without Project resource.

**Workaround**: Manually create projects, reference by ID

**Specification**: TBD

### Organization (Medium)

**What it does**: Top-level grouping for AAP resources (RBAC boundary)

**Why medium**: Enables multi-tenant AAP management. Currently must use existing orgs.

**Workaround**: Pre-create organizations, reference by ID

**Specification**: TBD

### Credential (Medium)

**What it does**: Stores authentication credentials for AAP to access external systems

**Why medium**: Required for Job Templates to authenticate to machines, vaults, clouds, etc.

**Workaround**: Pre-create credentials, reference by ID

**Specification**: TBD

### ExecutionEnvironment (Low)

**What it does**: Container image used to run Ansible jobs

**Why low**: AAP provides default EE. Custom EEs are advanced use case.

**Workaround**: Use default EE or pre-configure custom EEs

**Specification**: TBD

## Impact Analysis

### Without JobTemplate + Project

**What works**:
- ✅ Inventory/Host/Group management (declarative)
- ✅ Job execution (trigger existing templates)
- ✅ Workflow job execution

**What doesn't work**:
- ❌ Full GitOps workflow (templates must be created manually)
- ❌ Complete infrastructure-as-code (templates not in Git)
- ❌ Crossplane compositions with complete AAP stacks
- ❌ Automated template lifecycle management

**User impact**: Teams must maintain two sources of truth - Git for some resources, AAP UI for job templates.

### With JobTemplate + Project

**Unlocks**:
- ✅ Complete AAP stack in Git
- ✅ GitOps-ready automation
- ✅ Crossplane compositions defining full environments
- ✅ Declarative template versioning and rollback
- ✅ CI/CD validation of template definitions

## Engagement Strategy

### Phase 1: File Issues (Q2 2026)
- [ ] JobTemplate request filed
- [ ] Project request filed
- [ ] Organization request filed
- [ ] Credential request filed
- [ ] ExecutionEnvironment request filed

### Phase 2: Community Engagement (Q2-Q3 2026)
- [ ] Provide use cases and examples
- [ ] Answer maintainer questions
- [ ] Offer testing/validation assistance
- [ ] Collaborate on implementation if possible

### Phase 3: Monitor & Integrate (Q3-Q4 2026)
- [ ] Track terraform-provider-aap releases
- [ ] Test new resources when available
- [ ] Update aap-crossplane to include new resources
- [ ] Document migration path for users

### Phase 4: Fallback Plan (Q4 2026+)
If upstream provider stalls (6+ months no progress):
- [ ] Evaluate native Go provider implementation (see ADR-001)
- [ ] Cost/benefit analysis vs waiting for upstream
- [ ] Decision at ADR-001 review date (2026-09-30)

## Alternative: Native Go Provider

If Terraform provider cannot provide needed resources in a reasonable timeframe, the Crossplane provider can migrate to a native Go implementation. See:

- [ADR-001: Upjet vs Native](../adr/ADR-001-upjet-vs-native.md) - Decision rationale and review criteria
- [Roadmap: Migration Path](../ROADMAP.md#migration-path-upjet--native-go) - Implementation plan

**Estimated effort**: 3-6 months (1-2 engineers)

## Related Documentation

- [Roadmap](../ROADMAP.md) - Feature roadmap and timelines
- [ADR-001](../adr/ADR-001-upjet-vs-native.md) - Upjet decision
- [GitHub Issue Templates](../../.github/ISSUE_TEMPLATE/) - Tracking templates
- [AAP API Reference](https://docs.ansible.com/automation-controller/latest/html/controllerapi/) - API documentation

## Questions?

Open a [discussion](https://github.com/chadmf/aap-crossplane/discussions) or file an issue.
