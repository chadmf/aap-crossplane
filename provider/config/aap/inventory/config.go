package inventory

import (
	ujconfig "github.com/crossplane/upjet/v2/pkg/config"
)

// Configure configures the aap_inventory resource.
func Configure(p *ujconfig.Provider) {
	p.AddResourceConfigurator("aap_inventory", func(r *ujconfig.Resource) {
		r.Kind = "Inventory"
		r.ShortGroup = "aap"
	})
}
