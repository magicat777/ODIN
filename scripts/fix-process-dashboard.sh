#!/bin/bash

echo "=== Fixing Process Dashboard Memory Display ==="

# Create the updated dashboard JSON with correct memory queries
cat > /tmp/process-dashboard-update.json <<'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "host-process-monitoring",
    "title": "Host Process Monitoring - Ubuntu 22.04",
    "panels": [
      {
        "id": 2,
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "type": "table",
        "title": "Top Memory Consuming Processes (Resident)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "topk(10, sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype=\"resident\"}))",
            "format": "table",
            "instant": true,
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "bytes",
            "decimals": 0,
            "custom": {
              "align": "auto",
              "displayMode": "color-background-solid"
            }
          },
          "overrides": [
            {
              "matcher": {"id": "byName", "options": "groupname"},
              "properties": [
                {"id": "displayName", "value": "Process Name"},
                {"id": "custom.width", "value": 200}
              ]
            },
            {
              "matcher": {"id": "byName", "options": "Value"},
              "properties": [
                {"id": "displayName", "value": "Memory"},
                {"id": "custom.displayMode", "value": "gradient-gauge"}
              ]
            }
          ]
        }
      },
      {
        "id": 4,
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "type": "timeseries",
        "title": "Process Memory Usage Over Time (Resident)",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "topk(5, sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype=\"resident\"}))",
            "legendFormat": "{{ groupname }}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "bytes",
            "custom": {
              "drawStyle": "line",
              "lineWidth": 2,
              "fillOpacity": 10
            }
          }
        },
        "options": {
          "legend": {
            "displayMode": "table",
            "placement": "right",
            "calcs": ["mean", "max"]
          }
        }
      }
    ]
  },
  "overwrite": true
}
EOF

echo ""
echo "Manual Fix Instructions:"
echo "========================"
echo ""
echo "Since the dashboard isn't updating automatically, please update it manually:"
echo ""
echo "1. Open Grafana: http://odin.local:31494"
echo "2. Navigate to: Dashboards → Browse → Razer Blade → Host Process Monitoring"
echo "3. Click the settings gear icon (⚙️) in the top right"
echo "4. Select 'JSON Model' from the left menu"
echo ""
echo "5. Find these two panels and update their queries:"
echo ""
echo "   Panel: 'Top Memory Consuming Processes'"
echo "   Change the query from:"
echo "     topk(10, sum by (groupname) (namedprocess_namegroup_memory_bytes) / 1024 / 1024)"
echo "   To:"
echo "     topk(10, sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype=\"resident\"}))"
echo ""
echo "   And in fieldConfig.defaults, change:"
echo "     \"unit\": \"decmbytes\""
echo "   To:"
echo "     \"unit\": \"bytes\""
echo ""
echo "   Panel: 'Process Memory Usage Over Time'"
echo "   Change the query from:"
echo "     topk(5, sum by (groupname) (namedprocess_namegroup_memory_bytes) / 1024 / 1024 / 1024)"
echo "   To:"
echo "     topk(5, sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype=\"resident\"}))"
echo ""
echo "   And change the unit from \"GB\" to \"bytes\""
echo ""
echo "6. Click 'Save dashboard' at the top"
echo ""
echo "This will fix the memory display to show actual RAM usage instead of virtual memory."
echo ""
echo "Current real memory usage:"
kubectl exec -n monitoring deployment/prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=topk(5,sum%20by%20(groupname)%20(namedprocess_namegroup_memory_bytes{memtype="resident"}))' | jq -r '.data.result[] | "  • \(.metric.groupname): \(.value[1] | tonumber / 1024 / 1024 | round) MB"'