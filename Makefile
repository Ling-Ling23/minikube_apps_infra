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
	@echo "  deploy     - Apply infra (cert-manager issuers/certs, ingress) and app manifests"
	@echo "  logs       - Tail logs for pods matching NAME (regex; default 'backend|frontend') in NAMESPACE"
	@echo "  logs-backend  - Tail backend pod logs"
	@echo "  logs-frontend - Tail frontend pod logs"
	@echo "  ca-export  - Export local root CA to $(CA_FILE)"
	@echo "  cleanup    - Delete manifests applied by deploy"

.PHONY: deploy
deploy:
	$(KUBECTL) apply -f k8s/infra/cert-manager/cluster-issuer.yaml
	$(KUBECTL) apply -f k8s/infra/nginx/ingress.yaml
	$(KUBECTL) apply -f k8s/test_one/
	@echo "Waiting for deployments to be Available..."
	-$(KUBECTL) -n $(NAMESPACE) wait --for=condition=Available --timeout=90s deploy --all

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
	@mkdir -p $(dir $(CA_FILE))
	$(KUBECTL) -n $(NAMESPACE) get secret $(CA_SECRET) -o go-template='{{index .data "ca.crt"}}' | base64 -d > $(CA_FILE)
	@echo "Wrote $(CA_FILE)"

.PHONY: cleanup
cleanup:
	-$(KUBECTL) delete -f k8s/test_one/ --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/nginx/ingress.yaml --ignore-not-found
	-$(KUBECTL) delete -f k8s/infra/cert-manager/cluster-issuer.yaml --ignore-not-found
	@echo "Cleanup complete (controllers may recreate some cert-manager resources)."