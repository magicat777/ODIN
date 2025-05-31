#!/bin/bash
set -e

echo "=== Applying ODIN Platform Alerting Configuration ==="
echo "Timestamp: $(date)"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
echo "Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✓ Connected to cluster"
echo ""

# Apply alert rules ConfigMaps
echo "Applying alert rule configurations..."

echo "  - K3s core services alerts..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/k3s-alerts.yaml

echo "  - ODIN monitoring stack alerts..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/odin-stack-alerts.yaml

echo "  - AlertManager configuration..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/alertmanager-config.yaml

echo "  - Grafana alerting configuration..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/grafana-alerting-config.yaml

echo ""
echo "Updating deployments..."

# Update Prometheus deployment
echo "  - Updating Prometheus deployment..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/prometheus-deployment-updated.yaml

# Wait for Prometheus to be ready
echo "  - Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s

# Reload Prometheus configuration
echo "  - Reloading Prometheus configuration..."
kubectl exec -n monitoring deployment/prometheus -- kill -HUP 1

# Update AlertManager deployment
echo "  - Updating AlertManager deployment..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/alertmanager-deployment-updated.yaml

# Wait for AlertManager to be ready
echo "  - Waiting for AlertManager to be ready..."
kubectl wait --for=condition=ready pod -l app=alertmanager -n monitoring --timeout=120s

echo ""
echo "Verifying alert rules..."

# Check if Prometheus loaded the rules
sleep 5
RULES_COUNT=$(kubectl exec -n monitoring deployment/prometheus -- promtool query rules | grep -c "alerting" || true)
echo "  - Loaded $RULES_COUNT alerting rules"

# Check AlertManager status
AM_STATUS=$(kubectl exec -n monitoring deployment/alertmanager -- amtool config show 2>/dev/null | head -n 1 || echo "Unable to check")
echo "  - AlertManager status: $AM_STATUS"

echo ""
echo "=== Summary ==="
echo "✓ K3s core services alerts configured"
echo "✓ ODIN monitoring stack alerts configured"
echo "✓ AlertManager routing configured"
echo "✓ Grafana alerting provisioned"
echo ""
echo "Alert receivers configured:"
echo "  - default-receiver: All alerts"
echo "  - critical-receiver: Critical severity alerts (immediate)"
echo "  - k3s-receiver: K3s component alerts"
echo "  - gpu-receiver: GPU temperature/power alerts"
echo "  - monitoring-receiver: Monitoring stack alerts"
echo "  - claude-receiver: Claude Code usage alerts"
echo "  - power-receiver: Power/thermal alerts"
echo ""
echo "Access points:"
echo "  - Prometheus Alerts: http://localhost:31493/alerts"
echo "  - AlertManager: http://localhost:31495"
echo "  - Grafana Alerting: http://localhost:31494/alerting/list"
echo ""
echo "To test alerting:"
echo "  kubectl exec -n monitoring deployment/prometheus -- promtool query instant 'ALERTS{alertstate=\"firing\"}'"
echo ""
echo "✅ Alerting configuration complete!"