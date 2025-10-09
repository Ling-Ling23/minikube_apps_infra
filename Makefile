SHELL := bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
NAMESPACE ?= default
CA_SECRET ?= local-root-ca-secret
CA_FILE ?= k8s/local-root-ca.crt
NAME ?= backend|frontend

.PHONY: help
help:
	@echo "Targets:"
	@echo "  deploy-dev - Apply infra and app manifests with git metadata"
	@echo "  logs       - Tail logs for pods matching NAME (regex; default 'backend|frontend') in NAMESPACE"
	@echo "  logs-backend  - Tail backend pod logs"
	@echo "  logs-frontend - Tail frontend pod logs"
	@echo "  ca-export  - Export local root CA to $(CA_FILE)"
	@echo "  cleanup    - Delete manifests applied by deploy"
	@echo "  hpa-status - Show HorizontalPodAutoscaler status"
	@echo "  load-test  - Start load test to trigger HPA scaling"
	@echo "  stop-load-test - Stop load test"
	@echo "  install-prometheus - Install Prometheus stack via Helm (idempotent)"
	@echo "  setup-monitoring-ingress - Set up ingress for Grafana/Prometheus"
	@echo "  fix-monitoring-subpaths - Fix Grafana/Prometheus subpath configuration"
	@echo "  fix-grafana-loop - Fix Grafana redirect loop issue"
	@echo "  prometheus-ui - Access Grafana at http://localhost:3000"

.PHONY: deploy-all
deploy-all:
	@echo "Deploying app and setting up monitoring..."
	@echo "Certs needs to be done manually..."
	"$(MAKE)" ca-export
	"$(MAKE)" deploy-dev
	"$(MAKE)" install-prometheus
	"$(MAKE)" setup-monitoring-ingress
	"$(MAKE)" fix-monitoring-subpaths


.PHONY: deploy-dev
deploy-dev:
	@echo "Deploying with git metadata: SHA=$$(git rev-parse --short HEAD), BRANCH=$$(git branch --show-current), TIME=$$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	$(KUBECTL) apply -f k8s/infra/cert-manager/cluster-issuer.yaml
	$(KUBECTL) apply -f k8s/infra/nginx/ingress.yaml
	$(KUBECTL) apply -f k8s/apps/app_one/
	@echo "Waiting for deployments to be Available..."
	-$(KUBECTL) -n $(NAMESPACE) wait --for=condition=Available --timeout=90s deploy --all
	@echo "Git metadata available in: make logs-git or kubectl get deploy -o yaml | grep git-sha"

.PHONY: logs
logs:
	@echo "Tailing logs in namespace $(NAMESPACE) for pods matching '$(NAME)'..."
	@pod=$$($(KUBECTL) -n $(NAMESPACE) get pods -o name | grep -Ei '$(NAME)' | head -n1); \
	if [ -z "$$pod" ]; then echo "No pod found matching '$(NAME)' in $(NAMESPACE)"; exit 1; fi; \
	echo "Streaming: $$pod"; \
	$(KUBECTL) -n $(NAMESPACE) logs -f --all-containers "$$pod"

.PHONY: logs-backend logs-frontend
logs-backend:
	"$(MAKE)" logs NAME=backend

logs-frontend:
	"$(MAKE)" logs NAME=frontend

.PHONY: ca-export
ca-export:
	@echo "Exporting root CA from secret '$(CA_SECRET)' in $(NAMESPACE) to $(CA_FILE)"
	@if ! $(KUBECTL) -n $(NAMESPACE) get secret $(CA_SECRET) >/dev/null 2>&1; then \
		echo "Secret $(CA_SECRET) not found in namespace $(NAMESPACE)"; \
		exit 1; \
	fi
	@mkdir -p $(dir $(CA_FILE))
	@if [ -f "$(CA_FILE)" ]; then \
		echo "$(CA_FILE) already exists, checking if update needed..."; \
		current_hash=$$($(KUBECTL) -n $(NAMESPACE) get secret $(CA_SECRET) -o go-template='{{index .data "ca.crt"}}' | sha256sum | cut -d' ' -f1); \
		file_hash=$$(base64 "$(CA_FILE)" | tr -d '\n' | sha256sum | cut -d' ' -f1); \
		if [ "$$current_hash" = "$$file_hash" ]; then \
			echo "$(CA_FILE) is up-to-date"; \
		else \
			echo "Updating $(CA_FILE)..."; \
			$(KUBECTL) -n $(NAMESPACE) get secret $(CA_SECRET) -o go-template='{{index .data "ca.crt"}}' | base64 -d > $(CA_FILE); \
			echo "Updated $(CA_FILE)"; \
		fi; \
	else \
		echo "Creating $(CA_FILE)..."; \
		$(KUBECTL) -n $(NAMESPACE) get secret $(CA_SECRET) -o go-template='{{index .data "ca.crt"}}' | base64 -d > $(CA_FILE); \
		echo "Created $(CA_FILE)"; \
	fi

.PHONY: cleanup
cleanup:
	-$(KUBECTL) delete -f k8s/apps/app_one/ --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/nginx/ingress.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/cert-manager/cluster-issuer.yaml --ignore-not-found
	@echo "Cleaning up monitoring stack..."
	-helm uninstall prometheus -n monitoring
	-$(KUBECTL) delete -f k8s/infra/nginx/monitoring-ingress.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/cert-manager/monitoring-cert.yaml --ignore-not-found
	-$(KUBECTL) delete namespace monitoring --ignore-not-found
	@echo "Cleanup complete (controllers may recreate some cert-manager resources)."

.PHONY: install-prometheus
install-prometheus:
	@echo "Installing Prometheus stack via Helm..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	@if helm list -n monitoring | grep -q prometheus; then \
		echo "Prometheus already installed, skipping helm install"; \
	else \
		echo "Installing Prometheus stack..."; \
		helm install prometheus prometheus-community/kube-prometheus-stack \
		  --namespace monitoring --create-namespace \
		  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
		  --set grafana.grafana\\.ini.server.root_url=https://myapp.local/grafana \
		  --set grafana.grafana\\.ini.server.serve_from_sub_path=true; \
	fi
	@echo "Setting up monitoring ingress..."
	"$(MAKE)" setup-monitoring-ingress

.PHONY: prometheus-ui
prometheus-ui:
	@echo "Access Grafana at http://localhost:3000 (admin/prom-operator)"
	kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

.PHONY: setup-monitoring-ingress
setup-monitoring-ingress:
	@echo "Setting up monitoring ingress..."
	@if ! $(KUBECTL) get secret local-root-ca-secret -n monitoring >/dev/null 2>&1; then \
		echo "Copying CA secret to monitoring namespace..."; \
		$(KUBECTL) get secret local-root-ca-secret -n default -o yaml | \
		sed 's/namespace: default/namespace: monitoring/' | \
		sed '/resourceVersion:/d' | \
		sed '/uid:/d' | \
		sed '/creationTimestamp:/d' | \
		$(KUBECTL) apply -f -; \
	else \
		echo "CA secret already exists in monitoring namespace"; \
	fi
	$(KUBECTL) apply -f k8s/infra/cert-manager/monitoring-cert.yaml
	$(KUBECTL) apply -f k8s/infra/nginx/monitoring-ingress.yaml
	@echo "Monitoring ingress setup complete. Access via: https://myapp.local/grafana and https://myapp.local/prometheus"

.PHONY: fix-monitoring-subpaths
fix-monitoring-subpaths:
	@echo "Configuring Grafana and Prometheus for subpath serving..."
	helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring \
		--reuse-values \
		--set grafana.grafana\\.ini.server.root_url=https://myapp.local/grafana \
		--set grafana.grafana\\.ini.server.serve_from_sub_path=true \
		--set grafana.grafana\\.ini.server.domain=myapp.local \
		--set grafana.grafana\\.ini.server.enforce_domain=false \
		--set prometheus.prometheusSpec.externalUrl=https://myapp.local/prometheus \
		--set prometheus.prometheusSpec.routePrefix=/
	@echo "Waiting for pods to restart..."
	$(KUBECTL) rollout status deployment prometheus-grafana -n monitoring --timeout=120s
	$(KUBECTL) rollout status statefulset prometheus-prometheus-kube-prometheus-prometheus -n monitoring --timeout=120s
	@echo "Subpath configuration complete!"

.PHONY: fix-grafana-loop
fix-grafana-loop:
	@echo "Fixing Grafana redirect loop..."
	helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring \
		--reuse-values \
		--set grafana.grafana\\.ini.server.root_url=https://myapp.local/grafana/ \
		--set grafana.grafana\\.ini.server.serve_from_sub_path=true \
		--set grafana.grafana\\.ini.server.domain=myapp.local \
		--set grafana.grafana\\.ini.server.enforce_domain=false \
		--set grafana.grafana\\.ini.auth.disable_login_form=false \
		--set grafana.grafana\\.ini.auth.disable_signout_menu=false
	@echo "Restarting Grafana..."
	$(KUBECTL) rollout restart deployment prometheus-grafana -n monitoring
	$(KUBECTL) rollout status deployment prometheus-grafana -n monitoring --timeout=120s
	@echo "Grafana loop fix complete! Try accessing https://myapp.local/grafana again"

.PHONY: hpa-status
hpa-status:
	@echo "=== HorizontalPodAutoscaler Status ==="
	kubectl get hpa
	@echo ""
	@echo "=== Current Pod Replicas ==="
	kubectl get deployment py3miniapp-backend -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,READY:.status.readyReplicas
	@echo ""
	@echo "=== Recent HPA Events ==="
	kubectl describe hpa py3miniapp-backend-hpa | tail -10
