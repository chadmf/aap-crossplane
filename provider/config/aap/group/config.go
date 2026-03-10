package group

import (
	ujconfig "github.com/crossplane/upjet/v2/pkg/config"
)

// Configure configures the aap_group resource (AAP Group / Organization).
func Configure(p *ujconfig.Provider) {
	p.AddResourceConfigurator("aap_group", func(r *ujconfig.Resource) {
		r.Kind = "Group"
		r.ShortGroup = "aap"
	})
}
