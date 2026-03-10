# Crossplane Provider for Ansible Automation Platform


## TL;DR 
This is a prototype for creating a crossplane provider for the Ansible Automation Platform(AAP). The architecture design for creating a Crossplane Provider for the AAP is structured around bridging Kubernetes' declarative model with Ansible's task-driven execution.

---

## 1. Architectural Choice: Upjet vs. Native Go Provider

The recommendation is to start with **Upjet** due to the existing robust Terraform provider for AAP, which allows for instant generation of the majority of Crossplane Custom Resource Definitions (CRDs).

| Feature | Upjet (Terraform-Based) | Native (Go + Crossplane SDK) |
|---------|-------------------------|------------------------------|
| **Effort** | Low (Weeks) | High (Months) |
| **Logic Source** | Reuses Terraform Ansible Provider | Direct interaction with AAP REST API |
| **State** | Manages a `.tfstate` in K8s Secrets | No state file; queries AAP directly |
| **Reliability** | Inherits TF Provider bugs/limitations | Precise control over AAP-specific quirks |

---

## 2. Component Architecture

The provider must implement the **Crossplane Resource Model (XRM)** to manage AAP resources.

### Managed Resources (MRs)

Map key AAP entities to Kubernetes CRDs, including:

- **Organization**
- **Project**
- **Inventory** & **Host**
- **JobTemplate** (the executable unit)
- **WorkflowJobTemplate**

### ProviderConfig

An architected configuration that securely stores AAP connection details (URL, OAuth2 Token, or Username/Password), pulling from a Kubernetes Secret.

### Reconciler Loop

The controller for every resource must perform four key operations:

1. **Observe** — Call the AAP API (GET) to check for resource existence.
2. **Create** — If it doesn't exist, POST the desired state.
3. **Update** — If the AAP state differs from the YAML (drift), PATCH the AAP API.
4. **Delete** — If the CRD is deleted in K8s, DELETE the resource in AAP.

---

## 3. Handling the "Ansible Problem" (State vs. Action)

The biggest challenge is that Crossplane provisions **state** ("This Job Template should exist"), while Ansible performs **actions** ("Run this playbook now").

- **To manage AAP configuration:** Treat JobTemplates as static provisioning resources.
- **To trigger Jobs:** Architect a special CRD (e.g., `JobRun`) with a `v1alpha1` lifecycle. When this CRD is created, it triggers a job in AAP. A decision must be made on whether deleting the `JobRun` CRD should cancel the running job in AAP or do nothing.

---

## 4. Implementation Workflow (Upjet Approach)

The recommended technical steps for the Upjet path are:

| Step | Action |
|------|--------|
| **Initialize** | Use the [upjet-provider-template](https://github.com/upbound/upjet-provider-template) repository. |
| **Configure** | Point the generator to the existing Terraform provider for Ansible. |
| **Map** | Define which Terraform resources map to which K8s groups (e.g., `job.ansible.upbound.io`). |
| **Generate** | Run `make generate` to create the Go types and CRD manifests. |
| **Test** | Use a local Kind cluster to apply a JobTemplate YAML and verify it appears in the AAP UI. |

---

## 5. Security Architecture

- **RBAC:** Ensure the ServiceAccount running the Provider Pod has narrow permissions (only secrets and its own CRDs).
- **AAP Scoping:** Use AAP Application Tokens instead of admin passwords, scoping the tokens to specific AAP Organizations to minimize the blast radius.
