#!/bin/bash

echo "=== Importing ML Anomaly Detection Dashboard ==="
echo ""

# Create the dashboard JSON with proper format
cat > /tmp/ml-anomaly-import.json <<'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "ml-anomaly-detection",
    "title": "ML Anomaly Detection",
    "tags": ["odin", "anomaly", "ml", "ai"],
    "timezone": "browser",
    "schemaVersion": 38,
    "version": 1,
    "refresh": "30s",
    "panels": [
      {
        "datasource": "Prometheus",
        "gridPos": {"h": 4, "w": 24, "x": 0, "y": 0},
        "id": 1,
        "type": "text",
        "title": "",
        "options": {
          "mode": "markdown",
          "content": "# ML-Based Anomaly Detection\\n\\nAnomaly scores using machine learning:\\n- **0-40%**: Normal (Green)\\n- **40-60%**: Slight Deviation (Yellow)\\n- **60-80%**: Warning (Orange)\\n- **80-100%**: Critical (Red)"
        }
      },
      {
        "datasource": "Prometheus",
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 40},
                {"color": "orange", "value": 60},
                {"color": "red", "value": 80}
              ]
            },
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
        "id": 2,
        "type": "timeseries",
        "title": "GPU Temperature Anomaly Score",
        "targets": [{
          "expr": "anomaly_score{metric_name=\"nvidia_gpu_temperature_celsius\"}",
          "legendFormat": "GPU Temp Anomaly",
          "refId": "A"
        }]
      },
      {
        "datasource": "Prometheus",
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 40},
                {"color": "orange", "value": 60},
                {"color": "red", "value": 80}
              ]
            },
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
        "id": 3,
        "type": "timeseries",
        "title": "GPU Power Anomaly Score",
        "targets": [{
          "expr": "anomaly_score{metric_name=\"node_gpu_power_watts\"}",
          "legendFormat": "GPU Power Anomaly",
          "refId": "A"
        }]
      },
      {
        "datasource": "Prometheus",
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 40},
                {"color": "orange", "value": 60},
                {"color": "red", "value": 80}
              ]
            },
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 12},
        "id": 4,
        "type": "table",
        "title": "All Anomaly Scores",
        "targets": [{
          "expr": "anomaly_score",
          "format": "table",
          "instant": true,
          "refId": "A"
        }],
        "transformations": [{
          "id": "organize",
          "options": {
            "excludeByName": {
              "Time": true,
              "__name__": true,
              "job": true,
              "instance": true
            },
            "renameByName": {
              "metric_name": "Metric",
              "algorithm": "Algorithm", 
              "Value": "Anomaly Score"
            }
          }
        }]
      }
    ]
  },
  "folderId": 0,
  "overwrite": true
}
EOF

# Try to import via API
echo "Attempting to import dashboard via Grafana API..."
echo ""

# Try default credentials
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d @/tmp/ml-anomaly-import.json \
  http://odin.local:31494/api/dashboards/db 2>&1)

if echo "$RESPONSE" | grep -q "uid"; then
  echo "✅ Dashboard imported successfully!"
  echo ""
  echo "Access the dashboard at:"
  echo "http://odin.local:31494/d/ml-anomaly-detection/ml-anomaly-detection"
else
  echo "⚠️  Could not import dashboard automatically (authentication may be required)"
  echo ""
  echo "To import manually:"
  echo "1. Go to http://odin.local:31494/dashboards"
  echo "2. Click 'New' → 'Import'"
  echo "3. Copy the JSON from: /tmp/ml-anomaly-import.json"
  echo "4. Paste and click 'Load'"
  echo "5. Select 'ODIN' folder and click 'Import'"
fi

echo ""
echo "Current Anomaly Scores:"
kubectl exec -n monitoring deployment/prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=anomaly_score' | jq -r '.data.result[] | "  • \(.metric.metric_name): \(.value[1] | tonumber | round)% (\(.metric.algorithm))"'

rm -f /tmp/ml-anomaly-import.json