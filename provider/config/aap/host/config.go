package host

import (
	ujconfig "github.com/crossplane/upjet/v2/pkg/config"
)

// Configure configures the aap_host resource.
func Configure(p *ujconfig.Provider) {
	p.AddResourceConfigurator("aap_host", func(r *ujconfig.Resource) {
		r.Kind = "Host"
		r.ShortGroup = "aap"
	})
}
