# Crossplane Provider for Ansible Automation Platform

## TL;DR

This is a prototype for creating a crossplane provider for the Ansible Automation Platform(AAP). The architecture design for creating a Crossplane Provider for the AAP is structured around bridging Kubernetes' declarative model with Ansible's task-driven execution. The main goals of this is to test creating resources in AAP via kubernetes CRDs via crossplane and showing this is a viable solution going forward.

## Table of Contents

- [TL;DR](#tldr)
- [1. Architectural Choice: Upjet vs. Native Go Provider](#1-architectural-choice-upjet-vs-native-go-provider)
- [2. Component Architecture](#2-component-architecture)
  - [Managed Resources (MRs)](#managed-resources-mrs)
  - [ProviderConfig](#providerconfig)
  - [Reconciler Loop](#reconciler-loop)
- [3. Handling the "Ansible Problem" (State vs. Action)](#3-handling-the-ansible-problem-state-vs-action)
- [4. Implementation Workflow (Upjet Approach)](#4-implementation-workflow-upjet-approach)
- [5. Security Architecture](#5-security-architecture)
- [6. Build and Deploy on OpenShift](#6-build-and-deploy-on-openshift)
  - [6.1 Build the provider](#61-build-the-provider)
  - [6.2 Deploy AAP on OpenShift (AAP Operator)](#62-deploy-aap-on-openshift-aap-operator)
  - [6.3 Deploy Crossplane on OpenShift](#63-deploy-crossplane-on-openshift)
  - [6.4 Deploy the AAP Crossplane provider](#64-deploy-the-aap-crossplane-provider)
  - [6.5 Order of operations (summary)](#65-order-of-operations-summary)
  - [6.6 References](#66-references)
- [7. Documentation](#7-documentation)
  - [Build vs deploy overview](docs/README.md)
  - Build (provider image/package): [Build image (Podman)](docs/build/BUILD-PROVIDER-IMAGE.md), [Package image (xpkg)](docs/build/CROSSPLANE-PACKAGE-IMAGE.md), [Push to Quay](docs/build/PUSH-TO-QUAY-AND-OPENSHIFT.md)
  - Deploy: [OpenShift (full guide)](docs/deploy/openshift-deploy.md), [Deploy via Quay](docs/deploy/DEPLOY-AAP-PROVIDER-OPENSHIFT.md), [CRC / OpenShift Local](docs/deploy/DEPLOY-ON-CRC.md), [Validate provider vs AAP API](docs/deploy/VALIDATE-AAP-PROVIDER-API.md)
- [Workflows (CI)](workflows.md)

---

## 1. Architectural Choice: Upjet vs. Native Go Provider

The recommendation is to start with **Upjet** due to the existing robust Terraform provider for AAP, which allows for instant generation of the majority of Crossplane Custom Resource Definitions (CRDs).

| Feature | Upjet (Terraform-Based) | Native (Go + Crossplane SDK) |
| --- | --- | --- |
| **Effort** | Low (Weeks) | High (Months) |
| **Logic Source** | Reuses Terraform Ansible Provider | Direct interaction with AAP REST API |
| **State** | Manages a `.tfstate` in K8s Secrets | No state file; queries AAP directly |
| **Reliability** | Inherits TF Provider bugs/limitations | Precise control over AAP-specific quirks |

---

## 2. Component Architecture

The provider must implement the **Crossplane Resource Model (XRM)** to manage AAP resources.

### Managed Resources (MRs)

Map key AAP entities to Kubernetes CRDs, including:

- **Organization**
- **Project**
- **Inventory** & **Host**
- **JobTemplate** (the executable unit)
- **WorkflowJobTemplate**

### ProviderConfig

An architected configuration that securely stores AAP connection details (URL, OAuth2 Token, or Username/Password), pulling from a Kubernetes Secret.

### Reconciler Loop

The controller for every resource must perform four key operations:

1. **Observe** — Call the AAP API (GET) to check for resource existence.
2. **Create** — If it doesn't exist, POST the desired state.
3. **Update** — If the AAP state differs from the YAML (drift), PATCH the AAP API.
4. **Delete** — If the CRD is deleted in K8s, DELETE the resource in AAP.

---

## 3. Handling the "Ansible Problem" (State vs. Action)

The biggest challenge is that Crossplane provisions **state** ("This Job Template should exist"), while Ansible performs **actions** ("Run this playbook now").

- **To manage AAP configuration:** Treat JobTemplates as static provisioning resources.
- **To trigger Jobs:** Architect a special CRD (e.g., `JobRun`) with a `v1alpha1` lifecycle. When this CRD is created, it triggers a job in AAP. A decision must be made on whether deleting the `JobRun` CRD should cancel the running job in AAP or do nothing.

---

## 4. Implementation Workflow (Upjet Approach)

The recommended technical steps for the Upjet path are:

| Step | Action |
| --- | --- |
| **Initialize** | Use the [upjet-provider-template](https://github.com/upbound/upjet-provider-template) repository. |
| **Configure** | Point the generator to the existing Terraform provider for Ansible. |
| **Map** | Define which Terraform resources map to which K8s groups (e.g., `job.ansible.upbound.io`). |
| **Generate** | Run `make generate` to create the Go types and CRD manifests. |
| **Test** | Use a local Kind cluster to apply a JobTemplate YAML and verify it appears in the AAP UI. |

---

## 5. Security Architecture

- **RBAC:** Ensure the ServiceAccount running the Provider Pod has narrow permissions (only secrets and its own CRDs).
- **AAP Scoping:** Use AAP Application Tokens instead of admin passwords, scoping the tokens to specific AAP Organizations to minimize the blast radius.

---

## 6. Build and Deploy on OpenShift

This section describes how to **build** the AAP Crossplane provider, **deploy AAP** on OpenShift using the Red Hat Ansible Automation Platform Operator, then **deploy Crossplane and this provider** on the same (or another) OpenShift cluster so the provider can manage AAP resources declaratively.

### 6.1 Build the provider

From this repo, use the Upjet scaffold to generate and build the provider binary and CRDs:

1. Clone the [upjet-provider-template](https://github.com/crossplane/upjet-provider-template), run `hack/prepare.sh` with AAP naming (see [hack/prepare-aap.sh](hack/prepare-aap.sh)), then copy in the scaffold from `provider/` and merge [provider/Makefile.aap](provider/Makefile.aap) into the provider repo’s Makefile.
2. In the provider repo: `make generate.init`, `make generate`, then `make build`.

Full steps, prerequisites, and troubleshooting: **[BUILD.md](BUILD.md)**.

### 6.2 Deploy AAP on OpenShift (AAP Operator)

Deploy Ansible Automation Platform on OpenShift using the official operator so you have an AAP API endpoint for the Crossplane provider to talk to.

1. **Install the Ansible Automation Platform Operator** from OperatorHub (cluster-scoped, manual approval recommended):
   - OpenShift Console → **Operators** → **OperatorHub** → search for **Ansible Automation Platform**.
   - Install into a dedicated namespace (e.g. `aap`); choose a stable channel (e.g. `stable-2.4-cluster-scoped`).
   - [Red Hat: Deploying the AAP Operator on OpenShift](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.4/html-single/deploying_the_red_hat_ansible_automation_platform_operator_on_openshift_container_platform/index).

2. **Create an Automation controller instance** (the AAP controller):
   - Create an `AutomationController` or equivalent CR in the operator’s namespace and configure storage, replicas, and TLS as needed.
   - Wait for the controller to be ready and note the AAP URL (e.g. route or ingress) and admin credentials.

3. **Create an AAP Application Token** (recommended for the Crossplane provider): In AAP UI, create a token scoped to the desired organization(s) and save it for the provider’s `ProviderConfig` Secret.

### 6.3 Deploy Crossplane on OpenShift

Install Crossplane in a dedicated namespace (e.g. `crossplane-system`). Prefer the **Helm** install with security context set so OpenShift accepts the pods:

```bash
oc new-project crossplane-system

helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --set provider.packageRuntime.configuration.securityContext=false \
  --wait
```

Alternatively, use the **Crossplane OpenShift Operator** (OLM) if available in your catalog. See [Crossplane on OpenShift](https://blog.crossplane.io/crossplane-openshift-operator-cloud-native-services/) and [Installing Crossplane on OpenShift](https://github.com/jeremycaine/crossplane-with-openshift) for variations and security context notes.

**OpenShift:** Use the Helm values file [deploy/crossplane-values-openshift.yaml](deploy/crossplane-values-openshift.yaml) so Crossplane pods run with UIDs in the cluster’s restricted range; no SCC grants (e.g. `anyuid`) are required. See [docs/deploy/openshift-deploy.md](docs/deploy/openshift-deploy.md) for the full OpenShift deploy guide.

**CRC / OpenShift Local:** See [docs/deploy/DEPLOY-ON-CRC.md](docs/deploy/DEPLOY-ON-CRC.md) for namespace UID range, Quay-based provider images, and differences from full OpenShift.

Verify:

```bash
oc get pods -n crossplane-system
```

### 6.4 Deploy the AAP Crossplane provider

1. **Install the provider** into the cluster (use the image you built from the scaffold, or push to a registry and reference it):
   - Create a `Provider` resource that points to your provider image, or use `kubectl crossplane install provider` / the Crossplane CLI with the provider package.
   - Ensure the provider’s ServiceAccount has RBAC that allows reading Secrets (in the namespace where the `ProviderConfig` secret lives) and managing the provider’s CRDs.

2. **Create the AAP credentials Secret** in the same namespace as the provider (e.g. `crossplane-system`), with the AAP URL and an Application Token. See [deploy/aap-credentials-secret.yaml](deploy/aap-credentials-secret.yaml) for the format and `kubectl create secret` / `./deploy/create-aap-credentials-secret.sh` usage. Use the AAP URL from the Automation controller route/ingress (AAP 2.5+: gateway URL) and an Application Token scoped to the right organization.

3. **Create a ProviderConfig** that references this Secret (see [provider/examples/providerconfig.yaml](provider/examples/providerconfig.yaml)). Set `spec.credentials.secretRef` to the Secret name and key above.

4. **Apply managed resources** (e.g. `Inventory`, `Group`, `Host`) that reference this `ProviderConfig`; the provider will reconcile them against the AAP API.

### 6.5 Order of operations (summary)

| Step | Action |
| --- | --- |
| 1 | Build the provider from this repo’s scaffold ([BUILD.md](BUILD.md)). |
| 2 | Deploy AAP on OpenShift via the AAP Operator; create controller instance and obtain AAP URL + token. |
| 3 | Install Crossplane on OpenShift (Helm or OLM). |
| 4 | Install the AAP Crossplane provider and create Secret + ProviderConfig. |
| 5 | Create Crossplane MRs (Inventory, Group, etc.) and verify in the AAP UI. |

### 6.6 References

- [Deploying the AAP Operator on OpenShift](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.4/html-single/deploying_the_red_hat_ansible_automation_platform_operator_on_openshift_container_platform/index)
- [Deploying AAP 2 on Red Hat OpenShift](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.4/html/deploying_ansible_automation_platform_2_on_red_hat_openshift/)
- [Crossplane – OpenShift Operator](https://blog.crossplane.io/crossplane-openshift-operator-cloud-native-services/)
- [BUILD.md](BUILD.md) (this repo)

## 7. Documentation

Detailed guides are in [`docs/`](docs/), split into **build** (provider image/package) and **deploy** (Crossplane, credentials, provider install):

- [Build vs deploy overview](docs/README.md)
- **Build** (provider image/package): [Build image (Podman)](docs/build/BUILD-PROVIDER-IMAGE.md), [Package image (xpkg)](docs/build/CROSSPLANE-PACKAGE-IMAGE.md), [Push to Quay](docs/build/PUSH-TO-QUAY-AND-OPENSHIFT.md)
- **Deploy**: [OpenShift (full guide)](docs/deploy/openshift-deploy.md), [Deploy via Quay](docs/deploy/DEPLOY-AAP-PROVIDER-OPENSHIFT.md), [CRC / OpenShift Local](docs/deploy/DEPLOY-ON-CRC.md), [Validate provider vs AAP API](docs/deploy/VALIDATE-AAP-PROVIDER-API.md)
