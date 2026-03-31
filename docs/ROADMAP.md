# AAP Crossplane Provider Roadmap

This document tracks the feature roadmap for achieving full declarative AAP management via Crossplane.

**Last Updated**: 2026-03-31  
**Current Version**: v1alpha1 (prototype)

---

## Vision

Enable complete **infrastructure-as-code** for Ansible Automation Platform using Kubernetes CRDs, allowing teams to:
- Provision AAP resources declaratively (GitOps-ready)
- Manage job templates, projects, and automation workflows as YAML
- Trigger job execution via Kubernetes resources
- Monitor AAP state through Kubernetes status conditions

---

## Maturity Phases

### v1alpha1 (Current - Prototype)
**Goal**: Validate architectural approach, deliver core inventory management

**Status**: ✅ Complete

**Resources**:
- ✅ Inventory
- ✅ Host
- ✅ Group
- ✅ Job (launch/run)
- ✅ WorkflowJob

**Capabilities**:
- ✅ Basic CRUD operations for inventory resources
- ✅ Job execution triggering
- ✅ Orphan deletion policy
- ✅ Gateway-based API discovery
- ✅ Token and username/password authentication

**Known Limitations**:
- ❌ No JobTemplate management (blocked on upstream)
- ❌ No Project management
- ❌ No Organization management
- ❌ No E2E tests
- ❌ No automated build pipeline
- ⚠️ Manual post-generate fixes required

---

### v1beta1 (Next - Early Adopters)
**Goal**: Production-ready core features with stable API

**Target**: Q3 2026

**Requirements**:
1. **Build Automation** (In Progress)
   - ✅ Automated post-generate fixes ([#PR-TBD](https://github.com/chadmf/aap-crossplane/pulls))
   - ✅ E2E test suite with Kind + mock API
   - ⏳ CI/CD GitHub Actions workflow
   - ⏳ Automated Terraform provider version checks

2. **Documentation** (In Progress)
   - ✅ ADR-001: Upjet vs Native Go
   - ✅ ADR-002: Job CRD semantics
   - ⏳ API reference documentation
   - ⏳ User guide with common patterns

3. **Resource Coverage** (Blocked - see [Upstream Dependencies](#upstream-dependencies))
   - ⏳ JobTemplate CRD (requires Terraform provider support)
   - ⏳ Project CRD (requires Terraform provider support)
   - ⏳ Organization CRD (if available upstream)

4. **Quality Standards**
   - ⏳ No manual post-gen steps (scripted)
   - ⏳ E2E tests in CI
   - ⏳ Error message documentation
   - ⏳ 90% CRD field coverage from Terraform schema

**API Stability**: ⚠️ Minor breaking changes allowed (beta)

---

### v1.0 (Production)
**Goal**: Complete declarative AAP management

**Target**: Q1 2027

**Requirements**:
1. **Complete Resource Coverage**
   - ✅ Inventory, Host, Group
   - ✅ Job (run), WorkflowJob
   - 🎯 JobTemplate (full declarative workflow)
   - 🎯 Project
   - 🎯 Organization
   - 🎯 Credential
   - 🎯 ExecutionEnvironment

2. **Advanced Features**
   - 🎯 Status conditions reflecting AAP job state
   - 🎯 Job cancellation (Delete deletion policy option)
   - 🎯 Idempotency improvements (smart trigger detection)
   - 🎯 Retry policies for transient failures
   - 🎯 Custom validation webhooks

3. **Operational Excellence**
   - 🎯 Helm chart for easy installation
   - 🎯 Prometheus metrics
   - 🎯 Comprehensive test coverage (unit, integration, E2E)
   - 🎯 Performance benchmarks (large-scale reconciliation)
   - 🎯 Migration guide from v1beta1

4. **Security**
   - 🎯 RBAC examples for multi-tenant usage
   - 🎯 Token rotation support
   - 🎯 Secrets management best practices

**API Stability**: ✅ No breaking changes (v1)

---

## Resource Coverage Matrix

| Resource | v1alpha1 | v1beta1 | v1.0 | Blocker |
|----------|----------|---------|------|---------|
| **Inventory** | ✅ Full | ✅ | ✅ | None |
| **Host** | ✅ Full | ✅ | ✅ | None |
| **Group** | ✅ Full | ✅ | ✅ | None |
| **Job** (run) | ✅ Launch only | ✅ + status | ✅ + cancellation | None |
| **WorkflowJob** | ✅ Basic | ✅ + status | ✅ + dependencies | None |
| **JobTemplate** | ❌ | 🎯 Basic | ✅ Full | [Upstream TF provider](#upstream-dependencies) |
| **Project** | ❌ | 🎯 Basic | ✅ Full | [Upstream TF provider](#upstream-dependencies) |
| **Organization** | ❌ | 🎯 Basic | ✅ Full | [Upstream TF provider](#upstream-dependencies) |
| **Credential** | ❌ | ❌ | 🎯 Full | [Upstream TF provider](#upstream-dependencies) |
| **ExecutionEnvironment** | ❌ | ❌ | 🎯 Full | [Upstream TF provider](#upstream-dependencies) |

**Legend**:
- ✅ Available
- 🎯 Planned
- ⏳ In Progress
- ❌ Not Available

---

## Upstream Dependencies

### Terraform Provider: ansible/aap

**Current Version**: 1.4.0  
**Repository**: https://github.com/ansible/terraform-provider-aap  
**Status**: 🟡 Active (last release: TBD)

#### Missing Resources (Blockers)

| Resource | Status | GitHub Issue | Workaround |
|----------|--------|--------------|------------|
| `aap_job_template` | ❌ Not Available | [#TBD](https://github.com/ansible/terraform-provider-aap/issues) | Create manually in AAP UI/API, reference by ID |
| `aap_project` | ❌ Not Available | [#TBD](https://github.com/ansible/terraform-provider-aap/issues) | Create manually in AAP UI/API |
| `aap_organization` | ❌ Not Available | [#TBD](https://github.com/ansible/terraform-provider-aap/issues) | Use existing org, reference by ID |
| `aap_credential` | ❌ Not Available | [#TBD](https://github.com/ansible/terraform-provider-aap/issues) | Create manually, reference by ID |
| `aap_execution_environment` | ❌ Not Available | [#TBD](https://github.com/ansible/terraform-provider-aap/issues) | Use default EE or pre-configure |

#### Engagement Strategy

1. **File feature requests** for each missing resource with use cases
2. **Contribute upstream** if feasible (Go expertise required)
3. **Monitor release cycle** for new resource additions
4. **Evaluate native Go provider** if upstream stalls (see ADR-001 review criteria)

**Action Items**:
- [ ] Create upstream issues for JobTemplate, Project, Organization
- [ ] Engage with terraform-provider-aap maintainers
- [ ] Track release cadence (set alert for 6-month inactivity)

---

## Feature Flags

To enable development and testing of resources before upstream support is complete, the provider supports feature flags:

### Environment Variables

```bash
# Enable experimental JobTemplate support (requires custom TF provider fork)
export ENABLE_JOB_TEMPLATE=true

# Enable all experimental features
export ENABLE_EXPERIMENTAL=true

# Enable debug logging for feature flag evaluation
export FEATURE_FLAG_DEBUG=true
```

### Implementation

Feature flags are configured in `provider/config/provider.go`:

```go
// Feature flags for resources blocked on upstream
var (
    EnableJobTemplate = os.Getenv("ENABLE_JOB_TEMPLATE") == "true"
    EnableProject     = os.Getenv("ENABLE_PROJECT") == "true"
    EnableExperimental = os.Getenv("ENABLE_EXPERIMENTAL") == "true"
)

func Configure(p *ujconfig.Provider) {
    // Core resources (always enabled)
    configureInventory(p)
    configureHost(p)
    configureGroup(p)
    configureJob(p)
    configureWorkflowJob(p)

    // Experimental resources (gated)
    if EnableJobTemplate || EnableExperimental {
        configureJobTemplate(p) // Requires TF provider fork
    }
    if EnableProject || EnableExperimental {
        configureProject(p)
    }
}
```

**Usage**:

```bash
# Build provider with JobTemplate support
cd provider-aap
ENABLE_JOB_TEMPLATE=true make generate
ENABLE_JOB_TEMPLATE=true make build

# Deploy with feature flags
kubectl set env deployment/provider-aap -n crossplane-system \
    ENABLE_JOB_TEMPLATE=true
```

**Stability Warning**: Features behind flags are **experimental** and may have incomplete implementations or breaking changes.

---

## Migration Path: Upjet → Native Go

If Terraform provider stalls or limitations become blocking (see ADR-001 review criteria), migration to native Go provider:

### Phase 1: Parallel Implementation (3 months)
- Implement native Go controllers alongside Upjet
- Same CRD API (transparent to users)
- Feature parity validation suite

### Phase 2: Beta Testing (2 months)
- Feature flag to switch backends (`USE_NATIVE_CONTROLLERS=true`)
- Run both in parallel, compare reconciliation outcomes
- Performance benchmarking

### Phase 3: Migration (1 month)
- State migration tool (Terraform state → native format)
- User documentation and migration guide
- Gradual rollout (canary → full)

**Estimated Effort**: 6 months (1-2 engineers)  
**Decision Point**: 2026-09-30 (ADR-001 review date)

---

## Community & Support

### How to Contribute

1. **Report Issues**: [GitHub Issues](https://github.com/chadmf/aap-crossplane/issues)
2. **Feature Requests**: Label as `enhancement`, describe use case
3. **Pull Requests**: See [CONTRIBUTING.md](../CONTRIBUTING.md)
4. **Upstream Engagement**: Help file issues with terraform-provider-aap

### Communication

- **Slack**: Join `#crossplane` on Kubernetes Slack
- **Discussions**: [GitHub Discussions](https://github.com/chadmf/aap-crossplane/discussions)
- **Weekly Updates**: TBD

---

## Success Metrics

### v1beta1 Goals
- ✅ 10+ teams using in non-production
- ✅ <5 critical bugs per month
- ✅ CI passing >95% of time
- ✅ User documentation covers 90% of use cases

### v1.0 Goals
- ✅ 50+ teams using in production
- ✅ 99.5% provider uptime
- ✅ <1 critical bug per quarter
- ✅ Upstream Terraform provider actively maintained
- ✅ Native Go provider decision made (continue Upjet or migrate)

---

**Questions? Feedback?**  
Open an issue or discussion on [GitHub](https://github.com/chadmf/aap-crossplane).
