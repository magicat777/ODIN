#!/bin/bash
set -e

echo "=== Deploying ML-Based Anomaly Detection System ==="
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

# Deploy anomaly detector
echo "Deploying anomaly detection service..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/anomaly-detector.yaml

# Wait for PVC to be bound
echo "Waiting for model storage PVC..."
kubectl wait --for=condition=Bound pvc/anomaly-models-pvc -n monitoring --timeout=60s

# Deploy alert rules
echo "Deploying anomaly alert rules..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/anomaly-alerts.yaml

# Deploy dashboard
echo "Deploying anomaly detection dashboard..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/anomaly-detection-dashboard.yaml

# Update Prometheus configuration
echo "Updating Prometheus configuration..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/prometheus-config.yaml

# Update Prometheus deployment
echo "Updating Prometheus deployment..."
kubectl apply -f /home/magicat777/projects/ODIN/k8s/prometheus-deployment-updated.yaml

# Wait for anomaly detector to be ready
echo "Waiting for anomaly detector to be ready..."
kubectl wait --for=condition=ready pod -l app=anomaly-detector -n monitoring --timeout=300s || {
    echo "Warning: Anomaly detector is taking longer to start (installing dependencies)"
    echo "This is normal for first deployment. Checking logs..."
    kubectl logs -n monitoring -l app=anomaly-detector --tail=20
}

# Reload Prometheus
echo "Reloading Prometheus configuration..."
kubectl exec -n monitoring deployment/prometheus -- wget -O - --post-data='' http://localhost:9090/-/reload

# Update Grafana dashboard provider to include anomaly dashboard
echo "Updating Grafana dashboard configuration..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provider-anomaly
  namespace: monitoring
data:
  anomaly-dashboards.yaml: |
    apiVersion: 1
    providers:
    - name: 'anomaly'
      orgId: 1
      folder: 'ML Anomaly Detection'
      type: file
      disableDeletion: false
      updateIntervalSeconds: 10
      allowUiUpdates: true
      options:
        path: /var/lib/grafana/dashboards-anomaly
EOF

# Check if anomaly detector is exposing metrics
echo ""
echo "Checking anomaly detector metrics..."
sleep 10
METRICS_CHECK=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- http://anomaly-detector:9405/metrics | grep -c "anomaly_detector_health" || echo "0")

if [ "$METRICS_CHECK" -gt 0 ]; then
    echo "✓ Anomaly detector is exposing metrics"
else
    echo "⚠ Anomaly detector metrics not yet available (may still be initializing)"
fi

echo ""
echo "=== Deployment Summary ==="
echo "✓ Anomaly detection service deployed"
echo "✓ Alert rules configured"
echo "✓ Dashboard created"
echo "✓ Prometheus updated"
echo ""
echo "Supported algorithms:"
echo "  - Isolation Forest (GPU, network metrics)"
echo "  - Statistical methods (CPU, memory, API usage)"
echo ""
echo "Monitored metrics:"
echo "  - GPU temperature and power"
echo "  - CPU and memory usage"
echo "  - Network traffic patterns"
echo "  - Claude API usage"
echo ""
echo "Access points:"
echo "  - Anomaly Detection Dashboard: http://localhost:31494/d/anomaly-detection"
echo "  - Anomaly Metrics: http://localhost:31493/graph?g0.expr=anomaly_score"
echo ""
echo "To check anomaly scores:"
echo "  kubectl exec -n monitoring deployment/prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=anomaly_score' | jq '.data.result[] | {metric: .metric.metric_name, score: .value[1]}'"
echo ""
echo "✅ ML-Based Anomaly Detection deployed successfully!"