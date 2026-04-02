# ADR-001: Upjet (Terraform Wrapper) vs Native Go Provider

## Status

**Accepted** (2026-03-31)

## Context

Building a Crossplane provider for Ansible Automation Platform (AAP) requires implementing managed resources that interact with the AAP REST API. There are two primary approaches:

### Option 1: Native Go Provider
- Write custom Go controllers for each resource type
- Directly call AAP REST API using HTTP client
- Implement reconciliation, state management, and error handling from scratch
- Full control over behavior, retry logic, and error messages

### Option 2: Upjet (Terraform Provider Wrapper)
- Wrap the existing [Terraform ansible/aap provider](https://registry.terraform.io/providers/ansible/aap/latest)
- Generate Crossplane controllers automatically using Upjet framework
- Terraform provider handles API calls, state management, and retry logic
- Limited customization (bound to Terraform provider's behavior)

## Forces

### Time to Market
- **Native Go**: 3-6 months engineering time for core resources (Inventory, Host, Group, Job)
- **Upjet**: 2-4 weeks for scaffold, configuration, and validation

### Risk Profile
- **Native Go**: Higher initial risk (untested API integration), lower long-term risk (full control)
- **Upjet**: Lower initial risk (mature TF provider), higher long-term risk (dependency on upstream)

### Maintenance Burden
- **Native Go**: Maintain API client, state reconciliation, error handling, test suites
- **Upjet**: Maintain configuration wrappers, monitor Terraform provider updates, apply generator changes

### Feature Coverage
- **Native Go**: Can implement any AAP API capability (EDA, metrics, custom workflows)
- **Upjet**: Limited to what Terraform provider exposes (currently: Inventory, Host, Group, Job, WorkflowJob)

### Customization
- **Native Go**: Complete control over reconciliation logic, deletion policies, status conditions
- **Upjet**: Terraform provider behavior dictates retry logic, error messages, state handling

## Decision

**Use Upjet (Terraform wrapper) for the initial provider version (v1alpha1 → v1beta1).**

**Rationale**:

1. **Speed over perfection**: Delivering working AAP integration in weeks vs months provides immediate value to users and validates the use case before investing in native implementation

2. **Proven foundation**: The Terraform ansible/aap provider (1.4.0+) has battle-tested API handling, authentication, and error scenarios that would take months to replicate

3. **Reversible decision**: Starting with Upjet doesn't preclude migrating to native Go later. The Crossplane API surface (CRDs) can remain stable while changing the implementation

4. **Resource constraints**: Team bandwidth is better spent on user-facing features (CRD design, documentation, examples) than low-level API client development

5. **Prototype validation**: v1alpha1 is explicitly a prototype stage - acceptable to trade long-term control for short-term validation of the architectural approach

## Consequences

### What Becomes Easier

1. **Rapid iteration**: New AAP resources can be added by updating Upjet configuration and regenerating (hours, not weeks)
2. **Proven API handling**: Inherit Terraform provider's handling of AAP quirks (authentication, rate limiting, eventual consistency)
3. **Reduced test burden**: Terraform provider has comprehensive API integration tests
4. **Upstream bug fixes**: Security patches and AAP API changes are handled by Terraform provider maintainers

### What Becomes Harder

1. **Customization limits**: Cannot tune reconciliation frequency, backoff strategies, or validation logic without modifying generated code
2. **Terraform state opacity**: State lifecycle is managed by Upjet/Terraform - debugging drift requires understanding TF internals
3. **Dependency on upstream**: Breaking changes in Terraform provider (or provider abandonment) cascade to users
4. **Error message translation**: Terraform errors may not be optimal for Kubernetes users (e.g., "apply failed" vs "resource not ready")
5. **Generator coupling**: Upjet code generation changes can break post-generate manual fixes (see BUILD.md)

### Operational Impact

**For users**:
- Crossplane CRDs work as expected (apply YAML, get resources in AAP)
- Error messages may feel "Terraform-flavored" rather than Kubernetes-native
- Some AAP features may be unavailable if Terraform provider doesn't expose them

**For maintainers**:
- Fast feature delivery (add resources quickly)
- Must monitor Terraform provider releases for breaking changes
- Build process has manual post-generate steps (fragile, see ADR future item)

## Trade-offs

| Approach | Gained | Given Up | Cost if Reversed |
|----------|--------|----------|------------------|
| **Upjet** | Speed (weeks), proven API handling, upstream maintenance | Customization, state control, reconciliation tuning | 3-6 months engineering, ongoing maintenance burden |
| **Native Go** | Full control, custom logic, independence | Time (months), API testing burden, AAP quirk handling | N/A (could build later) |

## Acceptance Criteria

This decision is **accepted** if:

- ✅ Provider delivers working AAP resources (Inventory, Host, Group) in under 1 month
- ✅ Terraform provider (ansible/aap) receives regular updates (3+ releases/year)
- ✅ Generated code can be customized via Upjet configuration (no code generation forks)
- ✅ Users can deploy real workloads without hitting Terraform-imposed limitations

## Review Criteria

This ADR should be **revisited** when:

1. **Terraform provider stalls**: No releases for 6+ months, critical bugs unfixed
2. **Customization needs grow**: Users require retry logic, status conditions, or error handling that Upjet can't provide
3. **Feature gap widens**: AAP adds major capabilities (EDA automation, metrics APIs) not exposed by Terraform
4. **Provider reaches v1.0**: Maturity level where long-term maintenance cost outweighs short-term speed gains
5. **Upjet framework breaks**: Breaking changes in Upjet require major rework (at which point native may be cheaper)

**Scheduled review date**: 2026-09-30 (6 months)

## Migration Path (If Decision Changes)

If we decide to move to native Go:

1. **Parallel implementation**: Build native controllers alongside Upjet (same CRD API)
2. **Feature parity validation**: Ensure native version matches Terraform behavior
3. **Gradual migration**: Feature flag to switch between Upjet and native backends
4. **State migration**: Tool to convert Terraform state (K8s Secrets) to native format
5. **Documentation**: Clear migration guide for users (likely transparent if CRD API stays stable)

**Estimated effort**: 3-6 months (1-2 engineers)

## Related Decisions

- **ADR-002**: Job CRD semantics - constrained by Terraform provider's action-resource model
- **Future ADR**: Build automation (post-generate fixes need formalization)
- **Future ADR**: Feature flags for upstream-blocked resources (JobTemplate, Project)

## References

- Upjet framework: https://github.com/crossplane/upjet
- Terraform ansible/aap provider: https://registry.terraform.io/providers/ansible/aap/latest
- Crossplane provider architecture: https://docs.crossplane.io/latest/concepts/providers/
- Upjet provider template: https://github.com/upbound/upjet-provider-template
- Build documentation: [docs/build/BUILD.md](../build/BUILD.md)
