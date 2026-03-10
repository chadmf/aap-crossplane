package workflow_job

import (
	ujconfig "github.com/crossplane/upjet/v2/pkg/config"
)

// Configure configures the aap_workflow_job resource.
func Configure(p *ujconfig.Provider) {
	p.AddResourceConfigurator("aap_workflow_job", func(r *ujconfig.Resource) {
		r.Kind = "WorkflowJob"
		r.ShortGroup = "job"
	})
}
