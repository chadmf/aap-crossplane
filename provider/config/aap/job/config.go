package job

import (
	ujconfig "github.com/crossplane/upjet/v2/pkg/config"
)

// Configure configures the aap_job resource (job run / launch).
// Note: For managing Job Templates as declarative config, the Terraform provider
// may expose a separate resource; this configures the job execution resource.
func Configure(p *ujconfig.Provider) {
	p.AddResourceConfigurator("aap_job", func(r *ujconfig.Resource) {
		r.Kind = "Job"
		r.ShortGroup = "job"
	})
}
