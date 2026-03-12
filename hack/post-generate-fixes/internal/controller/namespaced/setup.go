package namespaced

import (
	"github.com/crossplane/upjet/v2/pkg/controller"
	ctrl "sigs.k8s.io/controller-runtime"

	"github.com/crossplane-contrib/provider-aap/internal/controller/namespaced/providerconfig"
)

// Setup creates all namespaced controllers with the supplied logger and adds them to
// the supplied manager.
func Setup(mgr ctrl.Manager, o controller.Options) error {
	return providerconfig.Setup(mgr, o)
}

// SetupGated creates all namespaced controllers with the supplied logger and adds them to
// the supplied manager gated.
func SetupGated(mgr ctrl.Manager, o controller.Options) error {
	return providerconfig.SetupGated(mgr, o)
}
