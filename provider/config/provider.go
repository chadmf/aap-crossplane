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
	"os"
	"strings"

	ujconfig "github.com/crossplane/upjet/v2/pkg/config"

	aapGroup        "github.com/crossplane-contrib/provider-aap/config/aap/group"
	aapHost         "github.com/crossplane-contrib/provider-aap/config/aap/host"
	aapInventory   "github.com/crossplane-contrib/provider-aap/config/aap/inventory"
	aapJob          "github.com/crossplane-contrib/provider-aap/config/aap/job"
	aapWorkflowJob  "github.com/crossplane-contrib/provider-aap/config/aap/workflow_job"
	// Experimental resources (blocked on upstream Terraform provider)
	// aapJobTemplate    "github.com/crossplane-contrib/provider-aap/config/aap/job_template"
	// aapProject        "github.com/crossplane-contrib/provider-aap/config/aap/project"
)

const (
	resourcePrefix = "aap"
	modulePath     = "github.com/crossplane-contrib/provider-aap"
)

//go:embed schema.json
var providerSchema string

//go:embed provider-metadata.yaml
var providerMetadata string

// Feature flags for experimental resources (blocked on upstream Terraform provider)
var (
	// EnableJobTemplate enables JobTemplate CRD (requires custom TF provider fork)
	EnableJobTemplate = getEnvBool("ENABLE_JOB_TEMPLATE", false)

	// EnableProject enables Project CRD (requires upstream TF provider support)
	EnableProject = getEnvBool("ENABLE_PROJECT", false)

	// EnableExperimental enables all experimental features
	EnableExperimental = getEnvBool("ENABLE_EXPERIMENTAL", false)

	// FeatureFlagDebug enables debug logging for feature flag evaluation
	FeatureFlagDebug = getEnvBool("FEATURE_FLAG_DEBUG", false)
)

// getEnvBool reads a boolean environment variable with a default fallback
func getEnvBool(key string, defaultValue bool) bool {
	val := os.Getenv(key)
	if val == "" {
		return defaultValue
	}
	return strings.ToLower(val) == "true" || val == "1"
}

// GetProvider returns the AAP provider configuration for controller-scoped managed resources
// (Inventory, Host, Group, Job, WorkflowJob), backed by the discovered controller API base.
// Gateway v1 and EDA endpoints are documented in ../AAP-HTTP-APIS.md; they are not separate MR kinds here yet.
//
// Feature flags control experimental resources (blocked on upstream Terraform provider):
//   - ENABLE_JOB_TEMPLATE=true - Enable JobTemplate CRD (requires TF provider fork)
//   - ENABLE_PROJECT=true - Enable Project CRD (requires upstream support)
//   - ENABLE_EXPERIMENTAL=true - Enable all experimental features
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

	// Core resources (always enabled)
	for _, configure := range []func(provider *ujconfig.Provider){
		aapGroup.Configure,
		aapHost.Configure,
		aapInventory.Configure,
		aapJob.Configure,
		aapWorkflowJob.Configure,
	} {
		configure(pc)
	}

	// Experimental resources (gated by feature flags)
	// Uncomment when Terraform provider adds support
	/*
	if EnableJobTemplate || EnableExperimental {
		if FeatureFlagDebug {
			fmt.Fprintf(os.Stderr, "[FeatureFlag] JobTemplate enabled\n")
		}
		aapJobTemplate.Configure(pc)
	}

	if EnableProject || EnableExperimental {
		if FeatureFlagDebug {
			fmt.Fprintf(os.Stderr, "[FeatureFlag] Project enabled\n")
		}
		aapProject.Configure(pc)
	}
	*/

	pc.ConfigureResources()
	return pc
}

// GetProviderNamespaced returns the provider configuration for namespaced resources.
// AAP resources are cluster-scoped; this returns nil so only cluster-scoped resources are generated.
func GetProviderNamespaced() *ujconfig.Provider {
	return nil
}
