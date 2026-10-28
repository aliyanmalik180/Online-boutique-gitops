# Online Boutique GitOps: local cluster helper.   Run `make help`.
# Pinned tool versions (change them here, nowhere else).
CLUSTER            ?= boutique
KIND_VERSION       := v0.33.0
ARGOCD_VERSION     := v3.5.2
INGRESS_NGINX_VER  := controller-v1.15.0
KPS_CHART_VERSION  := 92.13.0

ARGOCD_URL  := https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml
INGRESS_URL := https://raw.githubusercontent.com/kubernetes/ingress-nginx/$(INGRESS_NGINX_VER)/deploy/static/provider/kind/deploy.yaml

.DEFAULT_GOAL := help
.PHONY: help configure prereqs cluster ingress argocd deploy monitor up status \
        argocd-password argocd-ui grafana-password grafana-ui open destroy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

configure: ## Set your GitHub username in the ArgoCD manifests: make configure GH_USER=yourname
	@test -n "$(GH_USER)" || (echo "usage: make configure GH_USER=<github-username>"; exit 1)
	sed -i.bak 's/YOUR_GH_USER/$(GH_USER)/g' argocd/application-dev.yaml argocd/application-prod.yaml README.md docs/RUNBOOK.md && rm -f argocd/*.bak README.md.bak docs/*.bak
	@echo "Done. Commit and push, then run: make up"

prereqs: ## Check that the required tools are installed
	@for t in docker kind kubectl helm git; do \
		command -v $$t >/dev/null && echo "ok   $$t" || (echo "MISSING $$t"; exit 1); done
	@docker info >/dev/null 2>&1 && echo "ok   docker daemon running" || (echo "docker daemon is not running"; exit 1)
	@echo "kind version (want $(KIND_VERSION)): $$(kind version)"

cluster: ## Create the kind cluster (1 control-plane + 2 workers)
	@kind get clusters | grep -qx "$(CLUSTER)" && echo "cluster $(CLUSTER) already exists" || kind create cluster --name $(CLUSTER) --config kind/kind-config.yaml
	kubectl cluster-info --context kind-$(CLUSTER)
	kubectl get nodes

ingress: ## Install ingress-nginx (kind flavour, pinned)
	kubectl apply -f $(INGRESS_URL)
	kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=240s

argocd: ## Install ArgoCD (pinned)
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd --server-side --force-conflicts -f $(ARGOCD_URL)
	kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
	kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

deploy: ## Tell ArgoCD to watch this repo (dev environment)
	@grep -q YOUR_GH_USER argocd/application-dev.yaml && (echo "run: make configure GH_USER=<github-username> (then push)"; exit 1) || true
	kubectl apply -f argocd/application-dev.yaml
	@echo "Watch it sync:  kubectl -n argocd get applications -w"

monitor: ## Install Prometheus + Grafana (kube-prometheus-stack, pinned)
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		--version $(KPS_CHART_VERSION) -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m

up: prereqs cluster ingress argocd deploy ## Cluster + ingress + ArgoCD + app, in one go

status: ## Show nodes, ArgoCD apps and app pods
	kubectl get nodes
	kubectl -n argocd get applications
	kubectl -n boutique-dev get pods

argocd-password: ## Print the ArgoCD admin password (user: admin)
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

argocd-ui: ## Open ArgoCD UI at https://localhost:8081 (Ctrl+C to stop)
	kubectl -n argocd port-forward svc/argocd-server 8081:443

grafana-password: ## Print the Grafana admin password (user: admin)
	@kubectl -n monitoring get secret monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo

grafana-ui: ## Open Grafana at http://localhost:3000 (Ctrl+C to stop)
	kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

open: ## Print the store URL
	@echo "Store:  http://localhost:8080"

destroy: ## Delete the whole cluster
	kind delete cluster --name $(CLUSTER)
