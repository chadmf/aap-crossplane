---
name: Upstream Feature Request
about: Track a feature request for the Terraform ansible/aap provider
title: '[Upstream] '
labels: ['upstream', 'blocked', 'enhancement']
assignees: ''
---

## Upstream Repository

**Repository**: https://github.com/ansible/terraform-provider-aap  
**Issue**: [Link to upstream issue once created]

## Resource Needed

**Resource Name**: `aap_[resource_name]`  
**AAP API Endpoint**: `/api/controller/v2/[endpoint]/`

## Use Case

Describe what you're trying to accomplish with the AAP Crossplane provider that requires this resource.

**Example**:
> We want to manage AAP Job Templates declaratively via Crossplane CRDs, allowing teams to define templates in Git and apply them via kubectl. Currently, job templates must be created manually in the AAP UI, breaking the declarative workflow.

## Workaround

Describe the current workaround (if any):

**Example**:
> Create job templates manually in AAP UI or via direct API calls, then reference them by ID in Job CRDs.

## Acceptance Criteria

What would successful implementation look like?

- [ ] Terraform resource `aap_[resource_name]` is available in ansible/aap provider
- [ ] Resource supports CRUD operations (create, read, update, delete)
- [ ] Crossplane CRD generated via Upjet wraps the Terraform resource
- [ ] Example YAML provided in `examples/`
- [ ] E2E tests validate resource lifecycle

## Blocking

Does this block production usage of the AAP Crossplane provider?

- [ ] Yes - critical blocker
- [ ] No - nice to have

## Upstream Issue Template

Use this template when filing the issue with terraform-provider-aap:

```markdown
## Summary

Add support for managing AAP [Resource Name] via Terraform.

## Use Case

[Describe use case from above]

## Proposed Resource

**Name**: `aap_[resource_name]`  
**API Endpoint**: `/api/controller/v2/[endpoint]/`

**Example Configuration**:

```hcl
resource "aap_[resource_name]" "example" {
  name            = "Example [Resource]"
  organization_id = 1
  # ... additional fields
}
```

**Required Fields**:
- `name` - Resource name
- `organization_id` - Organization ID
- [List other required fields]

**Optional Fields**:
- [List optional fields]

## AAP API Documentation

[Link to AAP API docs for this resource]

## Related

- Crossplane provider issue: [Link to this issue]
```

## Engagement Plan

- [ ] File issue with terraform-provider-aap using template above
- [ ] Link upstream issue in this tracking issue
- [ ] Engage in upstream discussion (provide use cases, answer questions)
- [ ] Monitor for release that includes the resource
- [ ] Update AAP Crossplane provider to include new resource
- [ ] Close this tracking issue when available

## Timeline

**Upstream Filed**: [Date]  
**Expected Resolution**: [Estimate if known]  
**AAP Provider Updated**: [Date when integrated]

## References

- Terraform ansible/aap provider: https://registry.terraform.io/providers/ansible/aap/latest
- AAP API documentation: https://docs.ansible.com/automation-controller/latest/html/controllerapi/
- Crossplane Upjet: https://github.com/crossplane/upjet
