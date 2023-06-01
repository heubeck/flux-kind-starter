# the location where the necessary cli binaries are stored
binary_location = ${HOME}/.fks

# gitops repository to play with
gitops_repo = $(shell git config --get remote.origin.url)
gitops_branch = $(shell git branch --show-current)

# https://github.com/kubernetes-sigs/kind/releases
kind_version = 0.19.0
kind_arch = linux-amd64
kind_location = $(binary_location)/kind

# https://github.com/fluxcd/flux2/releases
flux_version = 2.0.0-rc.4
flux_arch = linux_amd64
flux_location = $(binary_location)/flux

.PHONY: check
check: # validate prerequisites
	### Checking prerequisites
	# Docker
	@docker version -f 'docker client version {{.Client.Version}}, server version {{.Server.Version}}'
	#
	# Kind ($(kind_location))
	@$(kind_location) --version
	#
	# Flux ($(flux_location))
	@$(flux_location) --version
	#
	# Kube Context
	@kubectl cluster-info | grep 127.0.0.1
	#
	# GitOps-Repository: $(gitops_repo)
	# GitOps-Branch: $(gitops_branch)
	# Everything is fine, lets get bootstrapped
	###

.PHONY: prepare
prepare: # install prerequisites
	# Creating $(binary_location)
	@mkdir -p $(binary_location)

	# Install or update kind $(kind_version) into $(kind_location)
	@curl -sSLo $(kind_location) "https://github.com/kubernetes-sigs/kind/releases/download/v$(kind_version)/kind-$(kind_arch)"
	@chmod a+x $(kind_location)

	# Install or update flux $(flux_version) into $(flux_location)
	@curl -sSLo $(flux_location).tgz https://github.com/fluxcd/flux2/releases/download/v$(flux_version)/flux_$(flux_version)_$(flux_arch).tar.gz
	@tar xf $(flux_location).tgz -C $(binary_location) && rm -f $(flux_location).tgz

.PHONY: new
new: # create fresh kind cluster
	# Creating kind cluster named 'flux-kind-starter'
	@$(kind_location) create cluster -n flux-kind-starter --config .kind/config.yaml
	@$(kind_location) export kubeconfig -n flux-kind-starter --kubeconfig ${HOME}/.kube/config

.PHONY: clean
clean: # remove kind cluster
	# Removing kind cluster named 'flux-kind-starter'
	@$(kind_location) delete cluster -n flux-kind-starter

gitops_repo_owner = $(shell echo $(gitops_repo) | cut -d/ -f4)
gitops_repo_name = $(shell echo $(gitops_repo) | cut -d/ -f5 | cut -d. -f1)

.PHONY: bootstrap
bootstrap: check # install and configure flux
ifndef GITHUB_TOKEN
	@echo "!!! please set GITHUB_TOKEN env to bootstrap flux"
	exit 1
endif
ifndef FLUX_PATH
	@echo "!!! please set FLUX_PATH for pointing to the desired flux bootstrap path"
	exit 1
endif
	### Bootstrapping flux from GitHub repo $(gitops_repo_owner)/$(gitops_repo_name) branch $(gitops_branch)
	$(flux_location) bootstrap github \
		--components-extra=image-reflector-controller,image-automation-controller \
		--read-write-key=true \
		--owner=$(gitops_repo_owner) \
		--repository=$(gitops_repo_name) \
		--branch=$(gitops_branch) \
		--path=${FLUX_PATH}
	#
	# Configuring GitHub commit status notification
	@kubectl create secret generic -n flux-system github --from-literal token=${GITHUB_TOKEN} --save-config --dry-run=client -o yaml | kubectl apply -f -
	@$(flux_location) create alert-provider github -n flux-system --type github --address "https://github.com/$(gitops_repo_owner)/$(gitops_repo_name)" --secret-ref github
	@$(flux_location) create alert -n flux-system --provider-ref github --event-source "Kustomization/*" flux-system
	@kubectl get kustomization -n flux-system
	###

.PHONY: reconcile
reconcile: # reconsule flux-system kustomization
	@$(flux_location) reconcile kustomization flux-system --with-source
	@kubectl get kustomization -n flux-system
