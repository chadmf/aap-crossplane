package cluster

import (
	"k8s.io/apimachinery/pkg/runtime"

	"github.com/crossplane-contrib/provider-aap/apis/cluster/v1alpha1"
	"github.com/crossplane-contrib/provider-aap/apis/cluster/v1beta1"
)

// AddToScheme adds all cluster-scoped AAP types to the given scheme.
func AddToScheme(s *runtime.Scheme) error {
	if err := v1alpha1.SchemeBuilder.AddToScheme(s); err != nil {
		return err
	}
	return v1beta1.SchemeBuilder.AddToScheme(s)
}
