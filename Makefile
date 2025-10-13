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
	@echo "  deploy-all - Full deployment: infra, app, monitoring, logging, storage"
	@echo "  deploy-init - Apply infra and app manifests with git metadata"
	@echo "  logs       - Tail logs for pods matching NAME (regex; default 'backend|frontend') in NAMESPACE"
	@echo "  logs-backend  - Tail backend pod logs"
	@echo "  logs-frontend - Tail frontend pod logs"
	@echo "  ca-export  - Export local root CA to $(CA_FILE)"
	@echo "  cleanup    - Delete manifests applied by deploy"
	@echo "  hpa-status - Show HorizontalPodAutoscaler status"
	@echo "  load-test  - Start load test to trigger HPA scaling"
	@echo "  stop-load-test - Stop load test"
	@echo "  pdb-status - Show PodDisruptionBudget status"
	@echo "  install-nginx-ingress - Install NGINX Ingress Controller via Helm"
	@echo "  install-prometheus - Install Prometheus stack via Helm (idempotent)"
	@echo "  install-openebs - Install OpenEBS for persistent storage"
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
	@echo "Deploying app and setting up monitoring with persistent logging..."
	@echo "Certs needs to be done manually..."
	"$(MAKE)" ca-export
	"$(MAKE)" install-nginx-ingress
	"$(MAKE)" deploy-init
	"$(MAKE)" install-openebs
	"$(MAKE)" install-prometheus
	"$(MAKE)" install-loki
	"$(MAKE)" setup-monitoring-ingress
	"$(MAKE)" fix-monitoring-subpaths


.PHONY: deploy-init
deploy-init:
	@echo "Deploying with git metadata: SHA=$$(git rev-parse --short HEAD), BRANCH=$$(git branch --show-current), TIME=$$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	@BRANCH=$$(git branch --show-current); \
	if [ "$$BRANCH" = "master" ] || [ "$$BRANCH" = "main" ]; then \
		BRANCH_VALUE="master"; \
	else \
		BRANCH_VALUE="$$BRANCH"; \
	fi; \
	echo "Setting PROJECT_GIT_BRANCH to: $$BRANCH_VALUE"; \
	$(KUBECTL) apply -f k8s/infra/cert-manager/cluster-issuer.yaml
	$(KUBECTL) apply -f k8s/infra/nginx/ingress.yaml
	$(KUBECTL) apply -f k8s/apps/app_one/serviceaccount_backend.yaml
	PROJECT_GIT_BRANCH=$$BRANCH_VALUE envsubst < k8s/apps/app_one/deployment_backend.yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -f k8s/apps/app_one/deployment_frontend.yaml
	$(KUBECTL) apply -f k8s/apps/app_one/service_backend.yaml
	$(KUBECTL) apply -f k8s/apps/app_one/service_frontend.yaml
	$(KUBECTL) apply -f k8s/apps/app_one/hpa_backend.yaml
	$(KUBECTL) apply -f k8s/apps/app_one/pdb_backend.yaml
	$(KUBECTL) apply -f k8s/apps/app_one/networkpolicy_backend_ingress.yaml
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
	@echo "Cleaning up application resources..."
	-$(KUBECTL) delete -f k8s/apps/app_one/ --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/nginx/ingress.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/cert-manager/cluster-issuer.yaml --ignore-not-found
	@echo "Cleaning up monitoring and logging stack..."
	-helm uninstall prometheus -n monitoring
	-helm uninstall loki -n monitoring
	-helm uninstall openebs -n openebs-system  
	-$(KUBECTL) delete -f k8s/infra/logging/fluent-bit-classic.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/monitoring/logs-dashboard.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/nginx/monitoring-ingress.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/cert-manager/monitoring-cert.yaml --ignore-not-found
	@echo "Cleaning up infrastructure components..."
	-helm uninstall nginx-ingress -n default --ignore-not-found
	-helm uninstall fluent-operator -n fluent --ignore-not-found
	-helm uninstall cert-manager -n cert-manager --ignore-not-found
	@echo "Cleaning up namespaces..."
	#-$(KUBECTL) delete namespace monitoring --ignore-not-found
	#-$(KUBECTL) delete namespace fluent-bit --ignore-not-found  
	#-$(KUBECTL) delete namespace openebs-system --ignore-not-found
	#-$(KUBECTL) delete namespace fluent --ignore-not-found
	#-$(KUBECTL) delete namespace cert-manager --ignore-not-found
	@echo "Cleanup complete (core Kubernetes components preserved)."

.PHONY: install-nginx-ingress
install-nginx-ingress:
	@echo "Installing NGINX Ingress Controller..."
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	@if helm list -n default | grep -q nginx-ingress; then \
		echo "NGINX Ingress already installed, skipping helm install"; \
	else \
		echo "Installing NGINX Ingress Controller..."; \
		helm install nginx-ingress ingress-nginx/ingress-nginx \
		  --namespace default; \
	fi
	@echo "Waiting for NGINX Ingress Controller to be ready..."
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx --timeout=120s
	@echo "NGINX Ingress Controller ready!"
	kubectl get service nginx-ingress-ingress-nginx-controller

.PHONY: install-openebs
install-openebs:
	@echo "Installing OpenEBS for persistent storage..."
	helm repo add openebs https://openebs.github.io/charts
	helm repo update
	@if helm list -n openebs-system | grep -q openebs; then \
		echo "OpenEBS already installed, skipping helm install"; \
	else \
		echo "Installing OpenEBS..."; \
		helm install openebs openebs/openebs \
		  --namespace openebs-system \
		  --create-namespace \
		  --set localprovisioner.enabled=true \
		  --set lvm-localpv.enabled=true \
		  --set zfs-localpv.enabled=false \
		  --set mayastor.enabled=false \
		  --set ndm.enabled=false \
		  --set ndmOperator.enabled=false; \
	fi
	@echo "Waiting for OpenEBS pods to be ready..."
	kubectl wait --for=condition=Ready pod -l component=localpv-provisioner -n openebs-system --timeout=120s
	kubectl wait --for=condition=Ready pod -l app=openebs-lvm-controller -n openebs-system --timeout=120s
	kubectl wait --for=condition=Ready pod -l app=openebs-lvm-node -n openebs-system --timeout=120s
	@echo "OpenEBS core components ready! Available storage classes:"
	kubectl get storageclass

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
		  --set loki.persistence.size=5Gi \
		  --set loki.persistence.storageClassName=openebs-hostpath; \
	fi
	@echo "Fixing Loki datasource default setting to prevent conflicts..."
	@sleep 5
	kubectl patch configmap loki-loki-stack -n monitoring --type='merge' -p='{"data":{"loki-stack-datasource.yaml":"apiVersion: 1\ndatasources:\n- name: Loki\n  type: loki\n  access: proxy\n  url: \"http://loki:3100\"\n  version: 1\n  isDefault: false\n  jsonData:\n    {}\n"}}' || true
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
		--set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=openebs-hostpath \
		--set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
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
