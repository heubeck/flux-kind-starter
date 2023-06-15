SHELL := /bin/bash

### the location where the necessary cli binaries are stored
binary_location = ${HOME}/.fks

### gitops repository and branch to play with
gitops_repo = $(shell git config --get remote.origin.url)
gitops_branch = $(shell git branch --show-current)
### used as folder within the repo to contain the root kustomization "flux-system" as well as the kind cluster name
cluster_name = local-cluster

### operating system, options are (darwin|linux)
os = $(shell uname -s | awk '{print tolower($$0)}')

### operating system, options are (amd64|arm64)
arch = $(shell [[ "$$(uname -m)" = x86_64 ]] && echo "amd64" || echo "$$(uname -m)")

### versions

# https://kubernetes.io/releases/
kubectl_version = v1.27.3
# https://github.com/kubernetes-sigs/kind/releases
kind_version = v0.20.0
# https://github.com/fluxcd/flux2/releases
flux_version = v2.0.0-rc.5

###

kubectl_arch = $(os)/$(arch)
kubectl_location = $(binary_location)/kubectl

kind_arch = $(os)-$(arch)
kind_location = $(binary_location)/kind

flux_arch = $(os)_$(arch)
flux_location = $(binary_location)/flux

### leave empty for enforcing docker even if podman was available, or set env NO_PODMAN=1
# kind_podman =
kind_podman = $(shell [[ "$$NO_PODMAN" -ne 1 ]] && which podman > /dev/null && echo "KIND_EXPERIMENTAL_PROVIDER=podman" || echo "")

kind_cmd = $(kind_podman) $(kind_location)

wait_timeout= "60s"

.PHONY: pre-check
pre-check: # validate required tools
	### Checking installed tooling
	# Podman or Docker
	@if [ -z "$(kind_podman)" ]; then \
		docker version -f 'docker client version {{.Client.Version}}, server version {{.Server.Version}}'; \
	else \
		podman -v; \
	fi
	#
	# Kubectl ($(kubectl_location))
	@$(kubectl_location) version --client=true --output=json | jq -r '"kubectl version "+ .clientVersion.gitVersion'
	#
	# Kind ($(kind_location))
	@$(kind_location) --version
	#
	# Flux ($(flux_location))
	@$(flux_location) --version
	#

gitops_repo_owner = $(shell [[ "$(gitops_repo)" = http* ]] && echo $(gitops_repo) | cut -d/ -f4 || echo $(gitops_repo) | cut -d: -f2 | cut -d/ -f1)
gitops_repo_name = $(shell [[ "$(gitops_repo)" = http* ]] && echo $(gitops_repo) | cut -d/ -f5 | cut -d. -f1 || echo $(gitops_repo) | cut -d/ -f2 | cut -d. -f1)

.PHONY: check
check: pre-check # validate prerequisites
	### Checking prerequisites
	# Kube Context
	@$(kubectl_location) cluster-info --context kind-$(cluster_name) | grep 127.0.0.1
	#
	# GitOps-Repository-Url: $(gitops_repo)
	# Repo-Owner: $(gitops_repo_owner)
	# Repo-Name: $(gitops_repo_name)
	# GitOps-Branch: $(gitops_branch)
	# Everything is fine, lets get bootstrapped
	#

kind_version_number = $(shell echo $(kind_version) | cut -c 2-)
flux_version_number = $(shell echo $(flux_version) | cut -c 2-)
kubectl_version_number = $(shell echo $(kubectl_version) | cut -c 2-)

.PHONY: prepare
prepare: # install prerequisites
	# Creating $(binary_location)
	@mkdir -p $(binary_location)

	# Install or update kind $(kind_version_number) for $(kind_arch) into $(kind_location)
	@curl -sSLfo $(kind_location) "https://github.com/kubernetes-sigs/kind/releases/download/v$(kind_version_number)/kind-$(kind_arch)"
	@chmod a+x $(kind_location)

	# Install or update flux $(flux_version_number) for $(flux_arch) into $(flux_location)
	@curl -sSLfo $(flux_location).tgz https://github.com/fluxcd/flux2/releases/download/v$(flux_version_number)/flux_$(flux_version_number)_$(flux_arch).tar.gz
	@tar xf $(flux_location).tgz -C $(binary_location) && rm -f $(flux_location).tgz
	@chmod a+x $(flux_location)

	# Install or update kubectl $(kubectl_version_number) for $(kubectl_arch) into $(kubectl_location)
	@curl -sSLfo $(kubectl_location) https://dl.k8s.io/release/$(kubectl_version)/bin/$(kubectl_arch)/kubectl
	@chmod a+x $(kubectl_location)

.PHONY: new
new: # create fresh kind cluster
	# Creating kind cluster named '$(cluster_name)'
	@$(kind_cmd) create cluster -n $(cluster_name) --config .kind/config.yaml
	@$(kind_cmd) export kubeconfig -n $(cluster_name) --kubeconfig ${HOME}/.kube/config

.PHONY: kube-ctx
kube-ctx: # create fresh kind cluster
	@$(kind_cmd) export kubeconfig -n $(cluster_name) --kubeconfig ${HOME}/.kube/config

.PHONY: clean
clean: # remove kind cluster
	# Removing kind cluster named '$(cluster_name)'
	@$(kind_cmd) delete cluster -n $(cluster_name)

.PHONY: bootstrap
bootstrap: check kube-ctx # install and configure flux
ifndef GITHUB_TOKEN
	@echo "!!! please set GITHUB_TOKEN env to bootstrap flux"
	exit 1
endif
	### Bootstrapping flux from GitHub repo $(gitops_repo_owner)/$(gitops_repo_name) branch $(gitops_branch)
	$(flux_location) bootstrap github \
		--components-extra=image-reflector-controller,image-automation-controller \
		--read-write-key=true \
		--owner=$(gitops_repo_owner) \
		--repository=$(gitops_repo_name) \
		--branch=$(gitops_branch) \
		--path=$(cluster_name)
	#
	# Configuring GitHub commit status notification
	@$(kubectl_location) create secret generic -n flux-system github --from-literal token=${GITHUB_TOKEN} --save-config --dry-run=client -o yaml | $(kubectl_location) apply -f -
	@$(flux_location) create alert-provider github -n flux-system --type github --address "https://github.com/$(gitops_repo_owner)/$(gitops_repo_name)" --secret-ref github
	@$(flux_location) create alert -n flux-system --provider-ref github --event-source "Kustomization/*" flux-system
	@$(kubectl_location) get kustomization -n flux-system
	#

.PHONY: reconcile
reconcile: # reconsule flux-system kustomization
	@$(flux_location) reconcile kustomization flux-system --with-source
	@$(kubectl_location) get kustomization -n flux-system

.PHONY: wait
wait: # wait for reconciliation complete
	@$(kubectl_location) wait --for=condition=ready --timeout=$(wait_timeout) kustomization -n flux-system flux-system
	@$(kubectl_location) wait --for=condition=ready --timeout=$(wait_timeout) kustomization -n flux-system infrastructure
	@$(kubectl_location) wait --for=condition=ready --timeout=$(wait_timeout) helmrelease -n ingress ingress-nginx
	@$(kubectl_location) wait --for=condition=ready --timeout=$(wait_timeout) helmrelease -n dashboard kubernetes-dashboard
	@$(kubectl_location) wait --for=condition=ready --timeout=$(wait_timeout) kustomization -n flux-system apps
