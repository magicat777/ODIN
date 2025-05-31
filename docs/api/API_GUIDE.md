# ODIN API Guide

## Overview

ODIN exposes multiple APIs for metrics collection, querying, alerting, and log management. This guide covers all available APIs, authentication methods, and common use cases.

## Table of Contents

1. [Prometheus API](#prometheus-api)
2. [Grafana API](#grafana-api)
3. [Loki API](#loki-api)
4. [AlertManager API](#alertmanager-api)
5. [Custom Exporter APIs](#custom-exporter-apis)
6. [Service Mesh APIs](#service-mesh-apis)
7. [Authentication & Security](#authentication--security)
8. [API Client Examples](#api-client-examples)

## Prometheus API

### Base URL
```
http://prometheus.monitoring.svc.cluster.local:9090
```

### Key Endpoints

#### 1. Query (Instant)
```http
GET /api/v1/query
```

**Parameters:**
- `query` (required): PromQL query string
- `time` (optional): Evaluation timestamp (RFC3339 or Unix timestamp)
- `timeout` (optional): Query timeout

**Example:**
```bash
curl -G http://prometheus:9090/api/v1/query \
  --data-urlencode 'query=up{job="prometheus"}'
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "up",
          "instance": "localhost:9090",
          "job": "prometheus"
        },
        "value": [1672531200, "1"]
      }
    ]
  }
}
```

#### 2. Query Range
```http
GET /api/v1/query_range
```

**Parameters:**
- `query` (required): PromQL query string
- `start` (required): Start timestamp
- `end` (required): End timestamp
- `step` (required): Query resolution step width

**Example:**
```bash
curl -G http://prometheus:9090/api/v1/query_range \
  --data-urlencode 'query=rate(prometheus_http_requests_total[5m])' \
  --data-urlencode 'start=2024-01-01T00:00:00Z' \
  --data-urlencode 'end=2024-01-01T01:00:00Z' \
  --data-urlencode 'step=60s'
```

#### 3. Series Metadata
```http
GET /api/v1/series
```

**Parameters:**
- `match[]` (required): Series selector
- `start` (optional): Start timestamp
- `end` (optional): End timestamp

**Example:**
```bash
curl -G http://prometheus:9090/api/v1/series \
  --data-urlencode 'match[]=node_cpu_seconds_total'
```

#### 4. Label Values
```http
GET /api/v1/label/<label_name>/values
```

**Example:**
```bash
curl http://prometheus:9090/api/v1/label/job/values
```

#### 5. Targets
```http
GET /api/v1/targets
```

**Parameters:**
- `state` (optional): Filter by target state (active, dropped, any)

**Example:**
```bash
curl http://prometheus:9090/api/v1/targets?state=active
```

#### 6. Rules
```http
GET /api/v1/rules
```

**Parameters:**
- `type` (optional): Filter by rule type (alert, record)

**Example:**
```bash
curl http://prometheus:9090/api/v1/rules?type=alert
```

#### 7. Alerts
```http
GET /api/v1/alerts
```

**Example:**
```bash
curl http://prometheus:9090/api/v1/alerts
```

### PromQL Query Examples

#### CPU Usage
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

#### Memory Usage
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

#### GPU Temperature
```promql
DCGM_FI_DEV_GPU_TEMP
```

#### GPU Memory Usage
```promql
DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100
```

#### Container CPU Usage
```promql
rate(container_cpu_usage_seconds_total{container!=""}[5m])
```

## Grafana API

### Base URL
```
http://grafana.monitoring.svc.cluster.local:3000
```

### Authentication
```bash
# Basic Auth
curl -u admin:password http://grafana:3000/api/org

# API Token
curl -H "Authorization: Bearer <API_TOKEN>" http://grafana:3000/api/org
```

### Key Endpoints

#### 1. Health Check
```http
GET /api/health
```

**Example:**
```bash
curl http://grafana:3000/api/health
```

**Response:**
```json
{
  "commit": "29e75ad97b",
  "database": "ok",
  "version": "10.0.0"
}
```

#### 2. Dashboards

##### List Dashboards
```http
GET /api/search
```

**Parameters:**
- `query` (optional): Search query
- `tag` (optional): Tag to search for
- `type` (optional): Type (dash-db, dash-folder)

**Example:**
```bash
curl -H "Authorization: Bearer <TOKEN>" \
  "http://grafana:3000/api/search?query=gpu"
```

##### Get Dashboard
```http
GET /api/dashboards/uid/:uid
```

**Example:**
```bash
curl -H "Authorization: Bearer <TOKEN>" \
  http://grafana:3000/api/dashboards/uid/gpu-metrics
```

##### Create/Update Dashboard
```http
POST /api/dashboards/db
```

**Body:**
```json
{
  "dashboard": {
    "id": null,
    "uid": "custom-dash",
    "title": "Custom Dashboard",
    "panels": [...]
  },
  "message": "Updated by API",
  "overwrite": false
}
```

#### 3. Data Sources

##### List Data Sources
```http
GET /api/datasources
```

**Example:**
```bash
curl -H "Authorization: Bearer <TOKEN>" \
  http://grafana:3000/api/datasources
```

##### Create Data Source
```http
POST /api/datasources
```

**Body:**
```json
{
  "name": "Prometheus-2",
  "type": "prometheus",
  "url": "http://prometheus:9090",
  "access": "proxy",
  "isDefault": false
}
```

#### 4. Alerts

##### List Alert Rules
```http
GET /api/v1/provisioning/alert-rules
```

**Example:**
```bash
curl -H "Authorization: Bearer <TOKEN>" \
  http://grafana:3000/api/v1/provisioning/alert-rules
```

##### Create Alert Rule
```http
POST /api/v1/provisioning/alert-rules
```

**Body:**
```json
{
  "uid": "gpu-temp-alert",
  "title": "GPU Temperature High",
  "condition": "A",
  "data": [
    {
      "refId": "A",
      "queryType": "",
      "model": {
        "expr": "DCGM_FI_DEV_GPU_TEMP > 80",
        "refId": "A"
      }
    }
  ],
  "noDataState": "NoData",
  "execErrState": "Alerting",
  "for": "5m",
  "annotations": {
    "summary": "GPU temperature is too high"
  }
}
```

#### 5. Users & Organizations

##### List Users
```http
GET /api/users
```

##### Get Current User
```http
GET /api/user
```

##### Update User
```http
PUT /api/users/:id
```

## Loki API

### Base URL
```
http://loki.monitoring.svc.cluster.local:3100
```

### Key Endpoints

#### 1. Query (Instant)
```http
GET /loki/api/v1/query
```

**Parameters:**
- `query` (required): LogQL query
- `limit` (optional): Max number of entries
- `time` (optional): Query timestamp

**Example:**
```bash
curl -G http://loki:3100/loki/api/v1/query \
  --data-urlencode 'query={job="varlogs"} |= "error"'
```

#### 2. Query Range
```http
GET /loki/api/v1/query_range
```

**Parameters:**
- `query` (required): LogQL query
- `start` (required): Start time
- `end` (required): End time
- `limit` (optional): Max entries per stream

**Example:**
```bash
curl -G http://loki:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="monitoring"}' \
  --data-urlencode 'start=2024-01-01T00:00:00Z' \
  --data-urlencode 'end=2024-01-01T01:00:00Z'
```

#### 3. Labels
```http
GET /loki/api/v1/labels
```

**Example:**
```bash
curl http://loki:3100/loki/api/v1/labels
```

#### 4. Label Values
```http
GET /loki/api/v1/label/<label_name>/values
```

**Example:**
```bash
curl http://loki:3100/loki/api/v1/label/job/values
```

#### 5. Push Logs
```http
POST /loki/api/v1/push
```

**Body:**
```json
{
  "streams": [
    {
      "stream": {
        "job": "custom-app",
        "level": "error"
      },
      "values": [
        ["1672531200000000000", "Error: Database connection failed"],
        ["1672531201000000000", "Error: Retry attempt 1"]
      ]
    }
  ]
}
```

### LogQL Query Examples

#### Find Errors
```logql
{job="varlogs"} |= "error" |~ "(?i)error|exception|fail"
```

#### Parse JSON Logs
```logql
{job="containerlogs"} | json | level="error"
```

#### Count by Level
```logql
sum by (level) (rate({job="app"} | json | __error__="" [5m]))
```

#### Extract Fields
```logql
{job="nginx"} | pattern "<ip> - - [<_>] \"<method> <path> <_>\" <status> <size>"
```

## AlertManager API

### Base URL
```
http://alertmanager.monitoring.svc.cluster.local:9093
```

### Key Endpoints

#### 1. List Alerts
```http
GET /api/v2/alerts
```

**Parameters:**
- `filter` (optional): Alert filter
- `active` (optional): Show only active alerts
- `silenced` (optional): Show only silenced alerts

**Example:**
```bash
curl http://alertmanager:9093/api/v2/alerts?active=true
```

#### 2. Create Alert
```http
POST /api/v2/alerts
```

**Body:**
```json
[
  {
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning"
    },
    "annotations": {
      "summary": "This is a test alert"
    },
    "startsAt": "2024-01-01T00:00:00Z",
    "endsAt": "2024-01-01T01:00:00Z"
  }
]
```

#### 3. Silences

##### List Silences
```http
GET /api/v2/silences
```

##### Create Silence
```http
POST /api/v2/silences
```

**Body:**
```json
{
  "matchers": [
    {
      "name": "alertname",
      "value": "GPUHighTemperature",
      "isRegex": false
    }
  ],
  "startsAt": "2024-01-01T00:00:00Z",
  "endsAt": "2024-01-01T02:00:00Z",
  "createdBy": "api",
  "comment": "Maintenance window"
}
```

#### 4. Alert Groups
```http
GET /api/v2/alerts/groups
```

**Example:**
```bash
curl http://alertmanager:9093/api/v2/alerts/groups
```

## Custom Exporter APIs

### Business Metrics Exporter
```
http://custom-exporter.monitoring.svc.cluster.local:8000/metrics
```

#### Custom Metrics Exposed
```
# HELP gpu_job_queue_length Number of jobs waiting for GPU
# TYPE gpu_job_queue_length gauge
gpu_job_queue_length 5

# HELP ml_model_accuracy Current ML model accuracy
# TYPE ml_model_accuracy gauge
ml_model_accuracy{model_name="resnet50"} 0.92
ml_model_accuracy{model_name="bert"} 0.89

# HELP api_requests_total Total API requests
# TYPE api_requests_total counter
api_requests_total{method="GET",endpoint="/api/v1/predict"} 1234
```

## Service Mesh APIs

### Linkerd Viz API
```
http://linkerd-viz.linkerd-viz.svc.cluster.local:8084
```

#### Metrics
```http
GET /api/metrics
```

**Parameters:**
- `resource_type`: pods, deployments, namespaces
- `resource_name`: Name of the resource
- `namespace`: Namespace

**Example:**
```bash
curl "http://linkerd-viz:8084/api/metrics?resource_type=deployment&resource_name=prometheus&namespace=monitoring"
```

## Authentication & Security

### API Authentication Methods

#### 1. Basic Authentication (Grafana)
```bash
curl -u admin:password http://grafana:3000/api/org
```

#### 2. Bearer Token (Grafana)
```bash
# Create API key
curl -X POST -H "Content-Type: application/json" \
  -u admin:password \
  -d '{"name":"monitoring-key","role":"Admin"}' \
  http://grafana:3000/api/auth/keys

# Use API key
curl -H "Authorization: Bearer <API_KEY>" \
  http://grafana:3000/api/dashboards/home
```

#### 3. OAuth2 Proxy
```bash
# Get OAuth token
TOKEN=$(curl -X POST https://github.com/login/oauth/access_token \
  -d "client_id=<CLIENT_ID>" \
  -d "client_secret=<CLIENT_SECRET>" \
  -d "code=<AUTH_CODE>" | jq -r .access_token)

# Use with API
curl -H "Authorization: Bearer $TOKEN" \
  http://oauth2-proxy:4180/api/dashboards
```

### Security Headers
```bash
# Recommended security headers for API calls
curl -H "X-Forwarded-User: monitoring-api" \
     -H "X-Forwarded-Groups: monitoring-admin" \
     -H "X-Forwarded-Email: api@company.com" \
     http://prometheus:9090/api/v1/query
```

## API Client Examples

### Python Client

```python
import requests
import json
from datetime import datetime, timedelta

class OdinAPIClient:
    def __init__(self, prometheus_url="http://localhost:9090", 
                 grafana_url="http://localhost:3000",
                 loki_url="http://localhost:3100"):
        self.prometheus_url = prometheus_url
        self.grafana_url = grafana_url
        self.loki_url = loki_url
        self.grafana_token = None
    
    def set_grafana_auth(self, token):
        """Set Grafana API token"""
        self.grafana_token = token
    
    # Prometheus queries
    def query_prometheus(self, query, time=None):
        """Execute instant query"""
        params = {"query": query}
        if time:
            params["time"] = time
        
        response = requests.get(f"{self.prometheus_url}/api/v1/query", params=params)
        return response.json()
    
    def query_prometheus_range(self, query, start, end, step="60s"):
        """Execute range query"""
        params = {
            "query": query,
            "start": start,
            "end": end,
            "step": step
        }
        
        response = requests.get(f"{self.prometheus_url}/api/v1/query_range", params=params)
        return response.json()
    
    def get_prometheus_targets(self):
        """Get all Prometheus targets"""
        response = requests.get(f"{self.prometheus_url}/api/v1/targets")
        return response.json()
    
    # Grafana operations
    def get_grafana_dashboards(self):
        """List all dashboards"""
        headers = {"Authorization": f"Bearer {self.grafana_token}"}
        response = requests.get(f"{self.grafana_url}/api/search", headers=headers)
        return response.json()
    
    def create_grafana_dashboard(self, dashboard_json):
        """Create new dashboard"""
        headers = {
            "Authorization": f"Bearer {self.grafana_token}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "dashboard": dashboard_json,
            "overwrite": False
        }
        
        response = requests.post(f"{self.grafana_url}/api/dashboards/db", 
                               headers=headers, 
                               json=payload)
        return response.json()
    
    # Loki queries
    def query_loki(self, query, limit=100):
        """Query logs from Loki"""
        params = {
            "query": query,
            "limit": limit
        }
        
        response = requests.get(f"{self.loki_url}/loki/api/v1/query", params=params)
        return response.json()
    
    def query_loki_range(self, query, start, end, limit=1000):
        """Query logs over time range"""
        params = {
            "query": query,
            "start": start,
            "end": end,
            "limit": limit
        }
        
        response = requests.get(f"{self.loki_url}/loki/api/v1/query_range", params=params)
        return response.json()
    
    # Utility methods
    def get_gpu_metrics(self):
        """Get current GPU metrics"""
        metrics = {}
        
        # Temperature
        temp_result = self.query_prometheus("DCGM_FI_DEV_GPU_TEMP")
        if temp_result["status"] == "success":
            for result in temp_result["data"]["result"]:
                gpu = result["metric"].get("gpu", "0")
                metrics[f"gpu_{gpu}_temp"] = float(result["value"][1])
        
        # Utilization
        util_result = self.query_prometheus("DCGM_FI_DEV_GPU_UTIL")
        if util_result["status"] == "success":
            for result in util_result["data"]["result"]:
                gpu = result["metric"].get("gpu", "0")
                metrics[f"gpu_{gpu}_util"] = float(result["value"][1])
        
        return metrics
    
    def get_system_health(self):
        """Get overall system health"""
        health = {
            "prometheus": self._check_prometheus_health(),
            "grafana": self._check_grafana_health(),
            "targets": self._check_targets_health()
        }
        return health
    
    def _check_prometheus_health(self):
        """Check Prometheus health"""
        try:
            response = requests.get(f"{self.prometheus_url}/-/healthy")
            return response.status_code == 200
        except:
            return False
    
    def _check_grafana_health(self):
        """Check Grafana health"""
        try:
            response = requests.get(f"{self.grafana_url}/api/health")
            data = response.json()
            return data.get("database") == "ok"
        except:
            return False
    
    def _check_targets_health(self):
        """Check scrape targets health"""
        targets = self.get_prometheus_targets()
        if targets["status"] == "success":
            active = targets["data"]["activeTargets"]
            healthy = sum(1 for t in active if t["health"] == "up")
            total = len(active)
            return {"healthy": healthy, "total": total}
        return {"healthy": 0, "total": 0}

# Example usage
if __name__ == "__main__":
    client = OdinAPIClient()
    
    # Get CPU usage
    cpu_query = '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
    cpu_result = client.query_prometheus(cpu_query)
    print(f"CPU Usage: {cpu_result}")
    
    # Get GPU metrics
    gpu_metrics = client.get_gpu_metrics()
    print(f"GPU Metrics: {gpu_metrics}")
    
    # Query logs
    log_query = '{namespace="monitoring"} |= "error"'
    logs = client.query_loki(log_query, limit=10)
    print(f"Recent errors: {len(logs.get('data', {}).get('result', []))} found")
    
    # Check system health
    health = client.get_system_health()
    print(f"System Health: {health}")
```

### Go Client

```go
package main

import (
    "context"
    "fmt"
    "time"
    
    "github.com/prometheus/client_golang/api"
    v1 "github.com/prometheus/client_golang/api/prometheus/v1"
    "github.com/prometheus/common/model"
)

type OdinClient struct {
    promAPI v1.API
}

func NewOdinClient(prometheusURL string) (*OdinClient, error) {
    client, err := api.NewClient(api.Config{
        Address: prometheusURL,
    })
    if err != nil {
        return nil, err
    }
    
    return &OdinClient{
        promAPI: v1.NewAPI(client),
    }, nil
}

// Query executes an instant query
func (c *OdinClient) Query(query string) (model.Value, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    result, warnings, err := c.promAPI.Query(ctx, query, time.Now())
    if err != nil {
        return nil, err
    }
    
    if len(warnings) > 0 {
        fmt.Printf("Warnings: %v\n", warnings)
    }
    
    return result, nil
}

// QueryRange executes a range query
func (c *OdinClient) QueryRange(query string, start, end time.Time, step time.Duration) (model.Value, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    r := v1.Range{
        Start: start,
        End:   end,
        Step:  step,
    }
    
    result, warnings, err := c.promAPI.QueryRange(ctx, query, r)
    if err != nil {
        return nil, err
    }
    
    if len(warnings) > 0 {
        fmt.Printf("Warnings: %v\n", warnings)
    }
    
    return result, nil
}

// GetTargets returns all scrape targets
func (c *OdinClient) GetTargets() (map[string][]v1.Target, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    targets, err := c.promAPI.Targets(ctx)
    if err != nil {
        return nil, err
    }
    
    return map[string][]v1.Target{
        "active":  targets.Active,
        "dropped": targets.Dropped,
    }, nil
}

// Example usage
func main() {
    client, err := NewOdinClient("http://localhost:9090")
    if err != nil {
        panic(err)
    }
    
    // Get CPU usage
    cpuQuery := `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
    result, err := client.Query(cpuQuery)
    if err != nil {
        panic(err)
    }
    fmt.Printf("CPU Usage: %v\n", result)
    
    // Get GPU temperature
    gpuQuery := `DCGM_FI_DEV_GPU_TEMP`
    gpuResult, err := client.Query(gpuQuery)
    if err != nil {
        panic(err)
    }
    fmt.Printf("GPU Temperature: %v\n", gpuResult)
    
    // Get targets
    targets, err := client.GetTargets()
    if err != nil {
        panic(err)
    }
    fmt.Printf("Active targets: %d\n", len(targets["active"]))
}
```

### Bash/cURL Examples

```bash
#!/bin/bash
# ODIN API Shell Client

PROMETHEUS_URL="http://localhost:9090"
GRAFANA_URL="http://localhost:3000"
LOKI_URL="http://localhost:3100"
ALERTMANAGER_URL="http://localhost:9093"

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    curl -s -G "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode "query=${query}" | jq .
}

# Function to get GPU metrics
get_gpu_metrics() {
    echo "=== GPU Metrics ==="
    
    # Temperature
    echo "Temperature:"
    query_prometheus "DCGM_FI_DEV_GPU_TEMP" | \
        jq -r '.data.result[] | "GPU \(.metric.gpu): \(.value[1])°C"'
    
    # Utilization
    echo -e "\nUtilization:"
    query_prometheus "DCGM_FI_DEV_GPU_UTIL" | \
        jq -r '.data.result[] | "GPU \(.metric.gpu): \(.value[1])%"'
    
    # Memory
    echo -e "\nMemory Used:"
    query_prometheus "DCGM_FI_DEV_FB_USED" | \
        jq -r '.data.result[] | "GPU \(.metric.gpu): \(.value[1] | tonumber / 1024 / 1024 | round)MB"'
}

# Function to get system metrics
get_system_metrics() {
    echo "=== System Metrics ==="
    
    # CPU
    echo "CPU Usage:"
    query_prometheus '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)' | \
        jq -r '.data.result[0].value[1] | tonumber | round | "\(.)%"'
    
    # Memory
    echo -e "\nMemory Usage:"
    query_prometheus '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100' | \
        jq -r '.data.result[] | "\(.metric.instance): \(.value[1] | tonumber | round)%"'
}

# Function to check targets health
check_targets() {
    echo "=== Target Health ==="
    curl -s "${PROMETHEUS_URL}/api/v1/targets" | \
        jq -r '.data.activeTargets[] | "\(.job): \(.health)"' | \
        sort | uniq -c
}

# Function to query logs
query_logs() {
    local query="$1"
    local limit="${2:-100}"
    
    curl -s -G "${LOKI_URL}/loki/api/v1/query" \
        --data-urlencode "query=${query}" \
        --data-urlencode "limit=${limit}" | \
        jq -r '.data.result[].values[][1]'
}

# Function to list active alerts
get_alerts() {
    echo "=== Active Alerts ==="
    curl -s "${ALERTMANAGER_URL}/api/v2/alerts?active=true" | \
        jq -r '.[] | "\(.labels.alertname) [\(.labels.severity)]: \(.annotations.summary)"'
}

# Main menu
case "$1" in
    gpu)
        get_gpu_metrics
        ;;
    system)
        get_system_metrics
        ;;
    targets)
        check_targets
        ;;
    logs)
        query_logs "${2:-{namespace=\"monitoring\"}}" "${3:-10}"
        ;;
    alerts)
        get_alerts
        ;;
    *)
        echo "Usage: $0 {gpu|system|targets|logs|alerts}"
        echo ""
        echo "Examples:"
        echo "  $0 gpu                    # Get GPU metrics"
        echo "  $0 system                 # Get system metrics"
        echo "  $0 targets                # Check target health"
        echo "  $0 logs '{job=\"app\"}'   # Query logs"
        echo "  $0 alerts                 # List active alerts"
        ;;
esac
```

## API Rate Limiting

### Prometheus
- Default: No built-in rate limiting
- Recommended: Use reverse proxy with rate limiting

### Grafana
- Built-in rate limiting via configuration
- Per-user and per-org limits available

### Loki
- Query timeout: 5 minutes default
- Max entries per query: configurable

## Best Practices

1. **Use Recording Rules**: For frequently used queries
2. **Implement Caching**: Cache query results when possible
3. **Set Timeouts**: Always set query timeouts
4. **Use Pagination**: For large result sets
5. **Monitor API Usage**: Track API call patterns
6. **Secure Endpoints**: Use authentication and TLS
7. **Version Your APIs**: Plan for API evolution
8. **Document Changes**: Keep API docs updated

## Troubleshooting

### Common Issues

1. **Query Timeout**
   - Reduce time range
   - Simplify query
   - Use recording rules

2. **No Data Returned**
   - Check metric names
   - Verify time range
   - Check target health

3. **Authentication Failed**
   - Verify credentials
   - Check token expiration
   - Review permissions

4. **Rate Limited**
   - Implement backoff
   - Cache results
   - Use bulk queries

## API Monitoring

Monitor your API usage:

```promql
# API request rate
rate(prometheus_http_requests_total[5m])

# API request duration
histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))

# API errors
rate(prometheus_http_requests_total{code=~"5.."}[5m])
```

## References

- [Prometheus API Docs](https://prometheus.io/docs/prometheus/latest/querying/api/)
- [Grafana HTTP API](https://grafana.com/docs/grafana/latest/developers/http_api/)
- [Loki API Docs](https://grafana.com/docs/loki/latest/api/)
- [AlertManager API](https://prometheus.io/docs/alerting/latest/management_api/)