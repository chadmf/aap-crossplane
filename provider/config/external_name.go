package config

import (
	"github.com/crossplane/upjet/v2/pkg/config"
)

// ExternalNameConfigs contains all external name configurations for the AAP provider.
// Terraform AAP provider resource names: aap_group, aap_host, aap_inventory, aap_job, aap_workflow_job.
var ExternalNameConfigs = map[string]config.ExternalName{
	"aap_group":         config.IdentifierFromProvider,
	"aap_host":         config.IdentifierFromProvider,
	"aap_inventory":   config.IdentifierFromProvider,
	"aap_job":         config.IdentifierFromProvider,
	"aap_workflow_job": config.IdentifierFromProvider,
}

// ExternalNameConfigurations applies all external name configs and sets the version of those
// resources to v1beta1 for resources that will be tested.
func ExternalNameConfigurations() config.ResourceOption {
	return func(r *config.Resource) {
		if e, ok := ExternalNameConfigs[r.Name]; ok {
			r.ExternalName = e
		}
	}
}

// ExternalNameConfigured returns the list of resources whose external name is configured.
func ExternalNameConfigured() []string {
	l := make([]string, 0, len(ExternalNameConfigs))
	for name := range ExternalNameConfigs {
		l = append(l, name+"$")
	}
	return l
}
