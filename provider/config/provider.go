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

// GetProvider returns the AAP provider configuration.
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
