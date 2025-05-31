# ODIN Makefile
.PHONY: help install test deploy-dev deploy-prod clean quickstart

NAMESPACE = monitoring
HELM_RELEASE = odin
K8S_CONTEXT = $(shell kubectl config current-context)

# Default target
help:
	@echo "ODIN Makefile Commands:"
	@echo "  make quickstart     - Run quick start script for initial setup"
	@echo "  make install        - Install dependencies"
	@echo "  make test          - Run all tests"
	@echo "  make deploy-phase1  - Deploy Phase 1 (Foundation)"
	@echo "  make deploy-phase2  - Deploy Phase 2 (Core Monitoring)"
	@echo "  make deploy-dev    - Deploy complete stack to dev"
	@echo "  make deploy-prod   - Deploy complete stack to prod"
	@echo "  make status        - Show deployment status"
	@echo "  make clean         - Clean up all resources"
	@echo "  make backup        - Backup monitoring data"

quickstart:
	@echo "Running ODIN quick start..."
	./scripts/quickstart.sh

install:
	@echo "Installing dependencies..."
	# Install NVIDIA device plugin
	kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
	# Add Helm repos
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add nvidia https://nvidia.github.io/gpu-monitoring-tools/helm-charts
	helm repo update

test:
	@echo "Running tests..."
	# Lint Helm charts
	@if [ -d "helm/charts/odin-monitoring" ]; then \
		helm lint helm/charts/odin-monitoring; \
	fi
	# Dry run Kubernetes manifests
	kubectl apply --dry-run=client -k k8s/base
	# Run Python tests
	@if [ -d "tests" ]; then \
		python -m pytest tests/ -v; \
	fi

deploy-phase1:
	@echo "Deploying Phase 1: Foundation..."
	# Create namespace
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	# Apply base configurations
	kubectl apply -f k8s/base/namespace.yaml
	kubectl apply -f k8s/base/rbac.yaml
	kubectl apply -f k8s/base/storage.yaml
	# Verify GPU access
	kubectl run gpu-test --rm -it --restart=Never --image=nvidia/cuda:11.8.0-base-ubuntu22.04 --limits=nvidia.com/gpu=1 -- nvidia-smi

deploy-phase2:
	@echo "Deploying Phase 2: Core Monitoring..."
	# Deploy Prometheus
	kubectl apply -f k8s/base/prometheus/
	# Deploy Grafana
	kubectl apply -f k8s/base/grafana/
	# Deploy Exporters
	kubectl apply -f k8s/base/exporters/
	# Wait for pods
	kubectl wait --for=condition=ready pod -l app=prometheus -n $(NAMESPACE) --timeout=300s
	kubectl wait --for=condition=ready pod -l app=grafana -n $(NAMESPACE) --timeout=300s

deploy-dev:
	@echo "Deploying to development environment..."
	kubectl apply -k k8s/overlays/dev
	@echo "Grafana will be available at: http://localhost:30300"

deploy-prod:
	@echo "Deploying to production environment..."
	@read -p "Are you sure you want to deploy to production? [y/N] " confirm && \
	if [ "$$confirm" = "y" ]; then \
		kubectl apply -k k8s/overlays/prod; \
	fi

status:
	@echo "=== ODIN Deployment Status ==="
	@echo "Current context: $(K8S_CONTEXT)"
	@echo ""
	@echo "Nodes:"
	@kubectl get nodes
	@echo ""
	@echo "Monitoring Namespace Pods:"
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "GPU Resources:"
	@kubectl describe nodes | grep -A 5 "nvidia.com/gpu" || echo "No GPU resources found"

clean:
	@echo "Cleaning up ODIN resources..."
	@read -p "This will delete all monitoring resources. Continue? [y/N] " confirm && \
	if [ "$$confirm" = "y" ]; then \
		kubectl delete namespace $(NAMESPACE) --ignore-not-found; \
		helm uninstall $(HELM_RELEASE) --namespace $(NAMESPACE) 2>/dev/null || true; \
	fi

backup:
	@echo "Backing up monitoring data..."
	./scripts/backup-monitoring.sh

logs:
	@echo "Showing logs for all monitoring pods..."
	kubectl logs -n $(NAMESPACE) -l app=prometheus --tail=50
	kubectl logs -n $(NAMESPACE) -l app=grafana --tail=50

port-forward:
	@echo "Setting up port forwards..."
	@echo "Prometheus: http://localhost:9090"
	@echo "Grafana: http://localhost:3000"
	@echo "Press Ctrl+C to stop"
	kubectl port-forward -n $(NAMESPACE) svc/prometheus 9090:9090 &
	kubectl port-forward -n $(NAMESPACE) svc/grafana 3000:3000

validate-gpu:
	@echo "Validating GPU configuration..."
	@kubectl get nodes -o json | jq '.items[].status.capacity | select(."nvidia.com/gpu" != null)'
	@kubectl run gpu-validate --rm -it --restart=Never \
		--image=nvidia/cuda:11.8.0-base-ubuntu22.04 \
		--limits=nvidia.com/gpu=1 \
		-- bash -c "nvidia-smi && echo 'GPU validation successful!'"

# Development helpers
shell-prometheus:
	kubectl exec -it -n $(NAMESPACE) deployment/prometheus -- sh

shell-grafana:
	kubectl exec -it -n $(NAMESPACE) deployment/grafana -- bash

# CI/CD targets
ci-validate:
	@echo "Running CI validation..."
	make test
	make deploy-dev
	make status

# Issue tracking helpers
issues-todo:
	@echo "=== TODO Issues ==="
	@grep -n "🟠 TODO" issues/ISSUE_TRACKER.md | head -20

issues-progress:
	@echo "=== In Progress Issues ==="
	@grep -n "🟡 IN_PROGRESS" issues/ISSUE_TRACKER.md

issues-blocked:
	@echo "=== Blocked Issues ==="
	@grep -n "🔴 BLOCKED" issues/ISSUE_TRACKER.md