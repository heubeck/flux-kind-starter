# Flux-Kind-Starter

A local Kubernetes setup using [Kind](https://kind.sigs.k8s.io/) and [Flux](https://fluxcd.io/) as template for your (and mine) experiments.

## Usage

* [Create a new repository](https://github.com/heubeck/flux-kind-starter/generate) from this template into your own profile.
* Clone it locally and step into its directory.
* Use [`make`](#make) for preparing your workstation and preparing the playground.

### `make`

Please have a look to the top section of the [`Makefile`](Makefile) to change its configuration for adopting it to your needs.

The included `Makefile` supports the following tasks:

* `make prepare`:
  Downloads the `kubectl`, `kind` and `flux` clis to `~/.fks` for later use. It's doesn't manipulate any of your regular local setup.

* `make pre-check`:
  Validates the required setup: podman or docker, kubectl, kind and flux.

* `make new`:
  Creates a new k8s kind cluster and points the local kube context to it.
  If available, _podman_ will be used unless env `NO_PODMAN=1` doesn't prevent it. Otherwise _docker_ is used.

* `make bootstrap`:
  Bootstraps flux to the local cluster, targeting the _this_ GitHub repository you're using and _the current_ checked out branch.
  `GITHUB_TOKEN` env needs to be configured with a repo-scoped GitHub personal access token

* `make check`:
  Runs automatically before _bootstrap_, validating the kube context and printing the targeted GitHub repository.

* `make wait`:
  Blocks til reconciliation finished and the cluster is ready to use.

* `make clean`:
  Removes the local kind cluster.

## What's in the box

* Kind [config](.kind/config.yaml) binding to host ports 8080 and 8443, so please free up those ports or change the config
* Basic GitOps setup with [nginx-ingress](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx) listing to those ports and
* [kubernetes-dashboard](https://github.com/kubernetes/dashboard/tree/master/charts/helm-chart/kubernetes-dashboard) accessible at http://localhost:8080/dashboard/
* An empty [apps](apps) folder targeted by a respective [kustomization](local-cluster/apps.yaml), ready to take your experiments

## Local requirements

While `kubectl`, `kind` and `flux` are managed with this repository (for version compatibility of everything in here), your local setup has to fulfill the following:

* `podman` (has precedence) or `docker` client available (and in case of docker configured properly to its daemon)
* `curl` for downloading the managed clis
* some common tools used by the Makefile:
  * `jq`
  * `cut`
  * `awk`
  * `which`
  * `tar` (with gzip support)

## Contribution

Please don't hesitate to file any issues or propose enhancements to this repo.
