# Crossplane Templates — Reference

Detailed patterns and links for native and Upjet providers.

## Native Provider Layout (provider-template)

- **APIs**: Group versions under `apis/` (e.g. `apis/v1alpha1`, `apis/database/v1alpha1`). One kind per file; `doc.go` for package docs and GVK vars.
- **Controllers**: Under `internal/controller/`. Register each managed resource in `register.go` via `SetupGated` (or equivalent).
- **Build**: Use crossplane-runtime v2; controller-runtime, Kubernetes client. Run `make reviewable` then `make build`.
- **Scaffolding**: Prefer copying an existing v1beta1+ resource from the same repo over kubebuilder; adapt to Crossplane patterns (ResourceSpec, ResourceStatus, Parameters in Spec, output-only in Status).

## Managed Resource Type Shape (Native)

```go
// Parameters: high-fidelity, writable API fields only
type FavouriteDBInstanceParameters struct {
    Name           string  `json:"name"`
    FancinessLevel int     `json:"fancinessLevel"`
    Version        *string `json:"version,omitempty"` // optional
}

type FavouriteDBInstanceSpec struct {
    xpv1.ResourceSpec  `json:",inline"`
    ForProvider FavouriteDBInstanceParameters `json:"forProvider"`
}

type FavouriteDBInstanceStatus struct {
    xpv1.ResourceStatus `json:",inline"`
    ID       int    `json:"id,omitempty"`
    Status   string `json:"status,omitempty"`
    Hostname string `json:"hostname,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster
type FavouriteDBInstance struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitempty"`
    Spec   FavouriteDBInstanceSpec   `json:"spec"`
    Status FavouriteDBInstanceStatus `json:"status,omitempty"`
}
```

## ExternalClient Semantics

- **Observe**: Return `ResourceExists: true/false`, `ResourceUpToDate: true/false`. Populate status and conditions. Optionally return `ConnectionDetails` for connection secrets.
- **Create**: Set `Creating` condition; return `ExternalCreation` and any connection details. Do not error if resource already exists (use `resource.Ignore(..., err)`).
- **Update**: Only mutable fields; return `ExternalUpdate{}`.
- **Delete**: Set `Deleting` condition; do not error if resource already gone.

## Upjet-Specific Configuration

- **External name**: How Crossplane maps to Terraform resource ID (e.g. `external_name` in config).
- **References**: Cross-resource refs (e.g. `project_id` → another MR).
- **Sensitive**: Mark sensitive params so they are stored in connection details / secrets.
- **Late initialization**: Behavior when the provider sets default or computed fields after create.

Config files live in the provider repo under the paths referenced by the Upjet generator (e.g. per-resource YAML or Go config).

## Official Links

- [Crossplane Provider Development Guide](https://github.com/crossplane/crossplane/blob/main/contributing/guide-provider-development.md)
- [provider-template](https://github.com/crossplane/provider-template) — native Go provider template
- [upjet-provider-template](https://github.com/crossplane/upjet-provider-template) — Upjet-based provider
- [Upjet: Generating a Provider](https://github.com/crossplane/upjet/blob/main/docs/generating-a-provider.md)
- [Upjet: Configuring a Resource](https://github.com/crossplane/upjet/blob/main/docs/configuring-a-resource.md)
- [Managed Resources (concepts)](https://docs.crossplane.io/latest/concepts/managed-resources/)
- [crossplane-runtime managed reconciler](https://pkg.go.dev/github.com/crossplane/crossplane-runtime/pkg/reconciler/managed)
