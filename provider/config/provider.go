// Package config holds Upjet provider configuration for Ansible Automation Platform (AAP).
//
// The embedded Terraform ansible/aap client discovers HTTP bases from GET {host}/api/:
//   - apis.controller → current_version → controller API (e.g. /api/controller/v2/); used by generated MRs.
//   - apis.eda → EDA paths; Terraform uses getEdaAPIEndpoint() for EDA datasources/actions.
//
// Platform gateway REST v1 lives under /api/gateway/v1/ (e.g. /api/gateway/v1/status/) on the same gateway host.
// See ../AAP-HTTP-APIS.md in this repo.
package config

import (
	_ "embed"

	ujconfig "github.com/crossplane/upjet/v2/pkg/config"

	aapGroup        "github.com/crossplane-contrib/provider-aap/config/aap/group"
	aapHost         "github.com/crossplane-contrib/provider-aap/config/aap/host"
	aapInventory   "github.com/crossplane-contrib/provider-aap/config/aap/inventory"
	aapJob          "github.com/crossplane-contrib/provider-aap/config/aap/job"
	aapWorkflowJob  "github.com/crossplane-contrib/provider-aap/config/aap/workflow_job"
)

const (
	resourcePrefix = "aap"
	modulePath     = "github.com/crossplane-contrib/provider-aap"
)

//go:embed schema.json
var providerSchema string

//go:embed provider-metadata.yaml
var providerMetadata string

// GetProvider returns the AAP provider configuration for controller-scoped managed resources
// (Inventory, Host, Group, Job, WorkflowJob), backed by the discovered controller API base.
// Gateway v1 and EDA endpoints are documented in ../AAP-HTTP-APIS.md; they are not separate MR kinds here yet.
func GetProvider() *ujconfig.Provider {
	pc := ujconfig.NewProvider(
		[]byte(providerSchema),
		resourcePrefix,
		modulePath,
		[]byte(providerMetadata),
		ujconfig.WithRootGroup("aap.crossplane.io"),
		ujconfig.WithIncludeList(ExternalNameConfigured()),
		ujconfig.WithFeaturesPackage("internal/features"),
		ujconfig.WithDefaultResourceOptions(
			ExternalNameConfigurations(),
		),
	)

	for _, configure := range []func(provider *ujconfig.Provider){
		aapGroup.Configure,
		aapHost.Configure,
		aapInventory.Configure,
		aapJob.Configure,
		aapWorkflowJob.Configure,
	} {
		configure(pc)
	}

	pc.ConfigureResources()
	return pc
}

// GetProviderNamespaced returns the provider configuration for namespaced resources.
// AAP resources are cluster-scoped; this returns nil so only cluster-scoped resources are generated.
func GetProviderNamespaced() *ujconfig.Provider {
	return nil
}
