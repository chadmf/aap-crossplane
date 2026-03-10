---
name: crossplane-templates
description: Applies Crossplane provider and template best practices when building providers, managed resources, ProviderConfig, or Upjet-generated CRDs. Use when creating or modifying Crossplane providers, CRDs, reconcilers, external clients, or when the user references provider-template, Upjet, XRM, or managed resources.
---

# Crossplane Provider & Template Best Practices

Apply these practices when building Crossplane providers, managed resources, or Upjet-generated templates.

---

## Choose the Right Path

| If… | Then… |
|-----|--------|
| A Terraform provider exists for the target API | Use **Upjet** (upjet-provider-template). Lower effort, reuses TF logic. |
| No Terraform provider or need full control | Use **native** (provider-template). Go + crossplane-runtime, more effort. |

---

## Managed Resources (XRM)

- **Spec**: Embed `xpv1.ResourceSpec` and a `ForProvider` (parameters) struct. Parameters = high-fidelity representation of the external API’s writable fields; use Kubernetes API conventions (e.g. `fancinessLevel` not `fanciness_level`).
- **Status**: Embed `xpv1.ResourceStatus`. Put output-only / read-only fields from the external API here, not in spec.
- **Markers**: Use `+kubebuilder:subresource:status` and `+kubebuilder:resource:scope=Cluster`.
- **Interface**: Satisfy `resource.Managed`; use angryjet or generator for getters/setters when building native providers.
- **Documentation**: Document every field in GoDoc; assume the reader is using `kubectl explain` or an API reference.

---

## ProviderConfig

- **Name**: Use exactly `ProviderConfig`.
- **Spec**: Embed `xpv1.ProviderSpec`. Store connection details (URL, OAuth2 token, or username/password) by referencing a Kubernetes Secret; avoid inline secrets.
- **Scope**: Cluster-scoped (`+kubebuilder:resource:scope=Cluster`).

---

## Reconciler Loop (Native Controllers)

The controller must implement four operations via `managed.ExternalClient`:

1. **Observe** — GET external resource; return `ResourceExists` and `ResourceUpToDate`. Copy output-only fields into status; set conditions (e.g. `Available`, `Creating`, `Deleting`).
2. **Create** — POST when resource does not exist. Return connection details if any. Use `resource.Ignore(IsNotFound/IsExists, err)` so create/delete are idempotent.
3. **Update** — PATCH when desired state differs from observed. Only called when `ResourceUpToDate` was false.
4. **Delete** — DELETE external resource when the MR is deleted (and deletion policy is Delete). Ignore “not found” errors.

Use `managed.NewReconciler` with an `ExternalConnecter` that builds the external API client from the ProviderConfig and its Secret.

---

## Upjet Workflow

When using Upjet (e.g. for this AAP provider):

1. **Initialize** — Start from [upjet-provider-template](https://github.com/crossplane/upjet-provider-template); run `./hack/prepare.sh` for provider name/group.
2. **Configure** — Set Makefile vars: `TERRAFORM_PROVIDER_SOURCE`, `TERRAFORM_PROVIDER_REPO`, `TERRAFORM_PROVIDER_VERSION`, `TERRAFORM_NATIVE_PROVIDER_BINARY`, `TERRAFORM_DOCS_PATH`.
3. **Map** — Define Terraform resources → Kubernetes API groups (e.g. `job.ansible.upbound.io`).
4. **Generate** — Run `make generate` for Go types and CRD manifests.
5. **Tune** — Configure external name, cross-resource references, sensitive fields, late init, and schema overrides in config as needed.
6. **Test** — Apply sample CRs (e.g. JobTemplate) in a Kind cluster and verify in the external system (e.g. AAP UI).

---

## Security

- **RBAC**: Restrict the provider’s ServiceAccount to the minimum required (e.g. secrets and its own CRDs).
- **Credentials**: Prefer scoped tokens (e.g. AAP Application Tokens per organization) over global admin credentials.

---

## Quality Checklist

Before considering a resource or provider “done”:

- [ ] Spec/status separation is correct (writable in spec, read-only in status).
- [ ] ProviderConfig references a Secret for credentials.
- [ ] Observe/Create/Update/Delete are idempotent where appropriate (ignore not-found/exists).
- [ ] Conditions and optional `ConnectionDetails` are set in Observe/Create.
- [ ] `make reviewable` (native) or `make generate` (Upjet) passes; CRDs and docs are generated.
- [ ] Package-level and type documentation live in `doc.go` or the right generated file so tooling picks them up.

---

## Additional Reference

For native provider structure, controller wiring, and code examples, see [reference.md](reference.md).
