# Upstream Request: JobTemplate Resource

**Status**: 🔴 Blocked  
**Priority**: Critical  
**Upstream Repository**: https://github.com/ansible/terraform-provider-aap  
**Tracking Issue**: [Create issue in aap-crossplane using upstream-request template]

---

## Summary

Request support for managing AAP Job Templates via Terraform ansible/aap provider.

**Impact**: This is the **highest priority** blocker for full declarative AAP management. Job Templates are the core automation unit in AAP, and without them, users cannot fully adopt infrastructure-as-code workflows.

---

## Use Case

### Current State (Broken Declarative Flow)

1. Define Inventory, Host, Group in Git as Crossplane MRs ✅
2. **Manually create JobTemplate in AAP UI** ❌ (breaks GitOps)
3. Copy JobTemplate ID from AAP UI
4. Define Job CR with hardcoded template ID
5. Apply to trigger job execution

### Desired State (Full Declarative)

1. Define Inventory, Host, Group in Git as Crossplane MRs ✅
2. **Define JobTemplate in Git as Crossplane MR** 🎯
3. Reference JobTemplate by name (not hardcoded ID)
4. Apply entire stack declaratively
5. Job execution triggered via Job CR

---

## Proposed Terraform Resource

**Name**: `aap_job_template`  
**API Endpoint**: `/api/controller/v2/job_templates/`  
**AAP Documentation**: https://docs.ansible.com/automation-controller/latest/html/controllerapi/api_ref.html#/Job_Templates

### Example Configuration

```hcl
resource "aap_job_template" "deploy_app" {
  name            = "Deploy Application"
  description     = "Deploy application to production"
  organization_id = 1
  inventory_id    = aap_inventory.production.id
  project_id      = aap_project.main.id  # Also blocked - see project request
  playbook        = "deploy.yml"
  
  # Execution environment
  execution_environment_id = 1
  
  # Job settings
  job_type        = "run"
  verbosity       = 0
  limit           = ""
  skip_tags       = ""
  
  # Credential associations (requires credential resource)
  credentials = [1, 2, 3]
  
  # Extra variables
  extra_vars = jsonencode({
    deployment_env = "production"
    version        = "1.2.3"
  })
  
  # Prompt settings
  ask_inventory_on_launch = false
  ask_limit_on_launch     = true
  ask_variables_on_launch = true
  
  # Concurrency
  allow_simultaneous = false
  
  # Webhooks
  enable_webhook      = false
  webhook_service     = ""
  webhook_credential  = null
}
```

### Required Fields

- `name` (string) - Job template name
- `organization_id` (int) - Organization ID
- `inventory_id` (int) - Inventory ID (or allow prompt)
- `project_id` (int) - Project ID
- `playbook` (string) - Playbook filename

### Optional Fields

- `description` (string)
- `job_type` (string) - "run" or "check"
- `execution_environment_id` (int)
- `credentials` (list of int) - Credential IDs
- `extra_vars` (string/JSON)
- `limit` (string)
- `verbosity` (int) - 0-5
- `skip_tags` (string)
- `start_at_task` (string)
- `timeout` (int)
- `allow_simultaneous` (bool)
- `ask_*_on_launch` (bool) - Prompt settings
- `webhook_*` - Webhook settings

### Computed Fields

- `id` (int) - Template ID
- `url` (string) - API URL
- `created` (timestamp)
- `modified` (timestamp)

---

## AAP API Structure

### Create Job Template

```http
POST /api/controller/v2/job_templates/
Content-Type: application/json

{
  "name": "Deploy Application",
  "description": "Deploy app to production",
  "organization": 1,
  "inventory": 2,
  "project": 3,
  "playbook": "deploy.yml",
  "job_type": "run",
  "extra_vars": "{\"env\":\"prod\"}"
}
```

### Update Job Template

```http
PATCH /api/controller/v2/job_templates/{id}/
Content-Type: application/json

{
  "description": "Updated description",
  "extra_vars": "{\"env\":\"staging\"}"
}
```

### Delete Job Template

```http
DELETE /api/controller/v2/job_templates/{id}/
```

### Get Job Template

```http
GET /api/controller/v2/job_templates/{id}/
```

---

## Implementation Notes

### Credential Association

Job templates can have multiple credentials. The Terraform resource should support:

```hcl
resource "aap_job_template" "example" {
  # ... other fields
  credentials = [
    aap_credential.ssh.id,
    aap_credential.vault.id,
  ]
}
```

API endpoint: `POST /api/controller/v2/job_templates/{id}/credentials/`

### Survey Spec

Job templates can have surveys (runtime prompts). Consider supporting:

```hcl
resource "aap_job_template" "example" {
  # ... other fields
  
  survey_enabled = true
  survey_spec = jsonencode({
    name = "Deployment Survey"
    description = "Parameters for deployment"
    spec = [
      {
        question_name    = "Environment"
        question_description = "Target environment"
        required         = true
        type            = "multiplechoice"
        variable        = "deploy_env"
        choices         = ["dev", "staging", "prod"]
        default         = "dev"
      }
    ]
  })
}
```

### Instance Groups

Job templates can be assigned to instance groups:

```hcl
resource "aap_job_template" "example" {
  # ... other fields
  instance_groups = [1, 2]
}
```

---

## Crossplane Integration

Once available in Terraform provider, the Crossplane CRD would look like:

```yaml
apiVersion: jobtemplate.aap.crossplane.io/v1alpha1
kind: JobTemplate
metadata:
  name: deploy-app
spec:
  forProvider:
    name: "Deploy Application"
    description: "Deploy app to production"
    organizationId: 1
    inventoryIdRef:
      name: production-inventory
    projectId: 3  # Blocked - see project request
    playbook: "deploy.yml"
    extraVars: |
      {
        "deployment_env": "production",
        "version": "1.2.3"
      }
    allowSimultaneous: false
    askVariablesOnLaunch: true
  providerConfigRef:
    name: default
  deletionPolicy: Delete
```

---

## Testing Strategy

Once implemented, validation should include:

1. **Create** - Template appears in AAP UI with correct settings
2. **Update** - Modify extra_vars, description → changes reflected
3. **Delete** - Template removed from AAP
4. **Credential Association** - Multiple credentials attached
5. **Survey** - Survey spec applied correctly
6. **Launch** - Job can be launched from template
7. **Import** - Existing templates can be imported

---

## Related Upstream Requests

**Dependencies** (should be filed together):
- **Project** (`aap_project`) - Required for template creation
- **Credential** (`aap_credential`) - Required for credential association
- **ExecutionEnvironment** (`aap_execution_environment`) - Optional but common

**Enables** (higher-level features):
- Full declarative AAP management
- GitOps workflows for automation
- Crossplane composition of complete AAP stacks

---

## Engagement

### Upstream Issue Template

```markdown
## Summary

Add Terraform resource for managing AAP Job Templates (`aap_job_template`).

## Use Case

Job Templates are the core automation unit in Ansible Automation Platform. Teams using Terraform (and Crossplane providers built on Terraform) need to manage job templates declaratively to enable full infrastructure-as-code workflows.

**Current workaround**: Manually create templates in AAP UI, then reference by ID in other automation. This breaks GitOps and declarative management.

**Desired state**: Define job templates as code alongside projects, inventories, and credentials.

## Proposed Resource

(Paste example configuration from above)

## API Endpoints

- `POST /api/controller/v2/job_templates/` - Create
- `GET /api/controller/v2/job_templates/{id}/` - Read
- `PATCH /api/controller/v2/job_templates/{id}/` - Update
- `DELETE /api/controller/v2/job_templates/{id}/` - Delete
- `POST /api/controller/v2/job_templates/{id}/credentials/` - Associate credential
- `POST /api/controller/v2/job_templates/{id}/instance_groups/` - Assign instance group

## References

- AAP API Docs: https://docs.ansible.com/automation-controller/latest/html/controllerapi/api_ref.html#/Job_Templates
- Crossplane AAP Provider: https://github.com/chadmf/aap-crossplane (blocked on this resource)
```

### Next Steps

1. [ ] File issue with terraform-provider-aap
2. [ ] Link issue in aap-crossplane tracking issue
3. [ ] Engage with maintainers, provide additional context
4. [ ] Monitor for release including job_template
5. [ ] Update Crossplane provider once available

---

**Priority Justification**: JobTemplate is the **most critical** missing resource. Without it, teams cannot achieve full declarative AAP management, which is the primary value proposition of the Crossplane provider.
