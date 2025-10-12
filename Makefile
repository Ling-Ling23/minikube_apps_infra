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
	@echo "  pdb-status - Show PodDisruptionBudget status"
	@echo "  install-prometheus - Install Prometheus stack via Helm (idempotent)"
	@echo "  install-loki - Install Loki stack for centralized logging"
	@echo "  install-fluent-bit - Install classic Fluent Bit DaemonSet (no operator)"
	@echo "  migrate-to-fluent - Replace Promtail with FluentOperator"
	@echo "  setup-logs-dashboard - Deploy logs dashboard to Grafana"
	@echo "  setup-monitoring-ingress - Set up ingress for Grafana/Prometheus"
	@echo "  fix-monitoring-subpaths - Fix Grafana/Prometheus subpath configuration"
	@echo "  fix-grafana-loop - Fix Grafana redirect loop issue"
	@echo "  prometheus-ui - Access Grafana at http://localhost:3000"
	@echo "  logs-loki-query - Query logs from Loki (backend, frontend, errors)"

.PHONY: deploy-all
deploy-all:
	@echo "Deploying app and setting up monitoring with logging..."
	@echo "Certs needs to be done manually..."
	"$(MAKE)" ca-export
	"$(MAKE)" deploy-dev
	"$(MAKE)" install-prometheus
	"$(MAKE)" install-loki
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
	@echo "Cleaning up monitoring and logging stack..."
	-helm uninstall prometheus -n monitoring
	-helm uninstall loki -n monitoring
	-$(KUBECTL) delete -f k8s/infra/logging/fluent-bit-classic.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/monitoring/logs-dashboard.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/nginx/monitoring-ingress.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/cert-manager/monitoring-cert.yaml --ignore-not-found
	-$(KUBECTL) delete namespace monitoring --ignore-not-found
	-$(KUBECTL) delete namespace fluent-bit --ignore-not-found
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

# Loki logging stack targets
.PHONY: install-loki
install-loki:
	@echo "Installing Loki stack via Helm..."
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	@if helm list -n monitoring | grep -q loki; then \
		echo "Loki already installed, skipping helm install"; \
	else \
		echo "Installing Loki stack..."; \
		helm install loki grafana/loki-stack \
		  --namespace monitoring \
		  --set grafana.enabled=false \
		  --set promtail.enabled=true \
		  --set loki.persistence.enabled=true \
		  --set loki.persistence.size=10Gi; \
	fi
	@echo "Setting up logs dashboard..."
	"$(MAKE)" setup-logs-dashboard

.PHONY: setup-logs-dashboard
setup-logs-dashboard:
	@echo "Deploying logs dashboard to Grafana..."
	$(KUBECTL) apply -f k8s/infra/monitoring/logs-dashboard.yaml
	@echo "Restarting Grafana to load dashboard..."
	$(KUBECTL) rollout restart deployment prometheus-grafana -n monitoring
	@echo "Dashboard will be available at: https://myapp.local/grafana/d/app-logs-001"

.PHONY: logs-loki-query logs-loki-backend logs-loki-frontend logs-loki-errors logs-loki-live
logs-loki-query:
	@echo "=== Loki Log Query Options ==="
	@echo "Backend logs:  make logs-loki-backend"
	@echo "Frontend logs: make logs-loki-frontend" 
	@echo "Error logs:    make logs-loki-errors"
	@echo "Live logs:     make logs-loki-live"
	@echo ""
	@echo "Or use Grafana Explore: https://myapp.local/grafana/explore"

logs-loki-backend:
	@echo "Querying backend logs from Loki (last 1h)..."
	@kubectl port-forward -n monitoring svc/loki 3100:3100 >/dev/null 2>&1 & \
	PID=$$!; \
	sleep 2; \
	echo "Recent backend logs:"; \
	curl -s "http://localhost:3100/loki/api/v1/query_range?query={pod=~\"py3miniapp-backend.*\"}&start=$$(date -d '1 hour ago' -u +%s)000000000&end=$$(date -u +%s)000000000&limit=20" | \
	jq -r '.data.result[]?.values[]?[1]' 2>/dev/null | head -20 || echo "Install jq for formatted output"; \
	kill $$PID 2>/dev/null || true

logs-loki-frontend:
	@echo "Querying frontend logs from Loki (last 1h)..."
	@kubectl port-forward -n monitoring svc/loki 3100:3100 >/dev/null 2>&1 & \
	PID=$$!; \
	sleep 2; \
	echo "Recent frontend logs:"; \
	curl -s "http://localhost:3100/loki/api/v1/query_range?query={pod=~\"py3miniapp-frontend.*\"}&start=$$(date -d '1 hour ago' -u +%s)000000000&end=$$(date -u +%s)000000000&limit=20" | \
	jq -r '.data.result[]?.values[]?[1]' 2>/dev/null | head -20 || echo "Install jq for formatted output"; \
	kill $$PID 2>/dev/null || true

logs-loki-errors:
	@echo "Querying error logs from Loki (last 1h)..."
	@kubectl port-forward -n monitoring svc/loki 3100:3100 >/dev/null 2>&1 & \
	PID=$$!; \
	sleep 2; \
	echo "Recent error logs:"; \
	curl -s "http://localhost:3100/loki/api/v1/query_range?query={namespace=\"default\"} |= \"error\"&start=$$(date -d '1 hour ago' -u +%s)000000000&end=$$(date -u +%s)000000000&limit=30" | \
	jq -r '.data.result[]?.values[]?[1]' 2>/dev/null | head -30 || echo "Install jq for formatted output"; \
	kill $$PID 2>/dev/null || true

logs-loki-live:
	@echo "=== Live Log Streaming Instructions ==="
	@echo "1. Open Grafana: https://myapp.local/grafana/explore"
	@echo "2. Select 'Loki' datasource from dropdown"
	@echo "3. Enter query: {pod=~\"py3miniapp.*\"}"
	@echo "4. Click 'Live' button for real-time streaming"
	@echo "5. Use time range selector for historical logs"
	@echo ""
	@echo "Useful queries:"
	@echo "  All app logs:    {pod=~\"py3miniapp.*\"}"
	@echo "  Backend only:    {pod=~\"py3miniapp-backend.*\"}"
	@echo "  Frontend only:   {pod=~\"py3miniapp-frontend.*\"}"
	@echo "  Error filtering: {namespace=\"default\"} |= \"error\""

# Classic Fluent Bit DaemonSet targets for replacing Promtail
.PHONY: install-fluent-bit migrate-to-fluent-bit test-fluent-logs remove-promtail
install-fluent-bit:
	@echo "Installing classic Fluent Bit DaemonSet..."
	$(KUBECTL) apply -f k8s/infra/logging/fluent-bit-classic.yaml
	@echo "Waiting for Fluent Bit pods to be ready..."
	$(KUBECTL) rollout status daemonset/fluent-bit -n fluent-bit --timeout=120s
	@echo "Fluent Bit DaemonSet deployed successfully!"
	@echo "Check pods: kubectl get pods -n fluent-bit"

migrate-to-fluent-bit:
	@echo "=== Migrating from Promtail to Fluent Bit DaemonSet ==="
	@echo "Step 1: Installing Fluent Bit alongside Promtail..."
	"$(MAKE)" install-fluent-bit
	@echo ""
	@echo "Step 2: Testing log collection (both will run temporarily)..."
	"$(MAKE)" test-fluent-logs
	@echo ""
	@echo "Step 3: Remove Promtail after confirming Fluent Bit works..."
	@echo "Run: make remove-promtail"

test-fluent-logs:
	@echo "=== Testing Fluent Bit Log Collection ==="
	@echo "Checking Fluent Bit pods..."
	$(KUBECTL) get pods -n fluent-bit
	@echo ""
	@echo "Checking resource usage comparison:"
	@echo "Promtail usage:"
	@kubectl top pods -n monitoring | grep promtail || echo "kubectl top not available"
	@echo "Fluent Bit usage:"
	@kubectl top pods -n fluent-bit | grep fluent-bit || echo "kubectl top not available"
	@echo ""
	@echo "Checking logs in Loki (should see both sources temporarily):"
	@echo "Open Grafana and check for logs with job=\"fluent-bit\" label"

remove-promtail:
	@echo "=== Removing Promtail (CAUTION: Make sure Fluent Bit is working!) ==="
	@read -p "Are you sure Fluent Bit is collecting logs correctly? (y/N): " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "Removing Promtail..."; \
		helm upgrade loki grafana/loki-stack -n monitoring \
		  --reuse-values \
		  --set promtail.enabled=false; \
		echo "Promtail removed. Only Fluent Bit now collecting logs."; \
	else \
		echo "Cancelled. Test Fluent Bit thoroughly before removing Promtail."; \
	fi

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

.PHONY: pdb-status
pdb-status:
	@echo "=== PodDisruptionBudget Status ==="
	kubectl get pdb
	@echo ""
	@echo "=== PDB Details ==="
	kubectl describe pdb py3miniapp-backend-pdb
	@echo ""
	@echo "=== Backend Pods ==="
	kubectl get pods -l app=py3miniapp-backend -o wide
