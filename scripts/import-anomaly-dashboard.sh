#!/bin/bash
set -e

echo "=== Importing Anomaly Detection Dashboard to Grafana ==="

# Extract dashboard JSON from ConfigMap
echo "Extracting dashboard JSON..."
kubectl get configmap anomaly-detection-dashboard -n monitoring -o jsonpath='{.data.anomaly-detection\.json}' > /tmp/anomaly-dashboard.json

# Port forward to Grafana
echo "Setting up port forward to Grafana..."
kubectl port-forward -n monitoring svc/grafana 3000:3000 &
PF_PID=$!
sleep 3

# Import dashboard via API
echo "Importing dashboard via Grafana API..."
curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d @/tmp/anomaly-dashboard.json \
  http://localhost:3000/api/dashboards/db

echo ""
echo "Dashboard imported successfully!"
echo ""
echo "Access the dashboard at:"
echo "http://localhost:31494/d/anomaly-detection/odin-ml-anomaly-detection"
echo ""
echo "Or via port-forward:"
echo "http://localhost:3000/d/anomaly-detection/odin-ml-anomaly-detection"

# Clean up
kill $PF_PID 2>/dev/null
rm -f /tmp/anomaly-dashboard.json

echo ""
echo "✅ Dashboard import complete!"