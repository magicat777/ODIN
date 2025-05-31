# Phase 3: Logging & Alerting Implementation Plan

## Overview
Phase 3 implements centralized logging with Loki/Promtail and alerting with AlertManager. All commands are designed for Claude to execute without sudo privileges.

## Prerequisites from Phase 2
- [ ] Prometheus operational with persistence
- [ ] Grafana accessible and configured
- [ ] All exporters collecting metrics
- [ ] Basic dashboards functional

## Sprint 5: Logging Infrastructure (Week 5)

### Day 1-2: Loki Deployment

#### Task ODIN-033: Deploy Loki
```bash
# Create Loki configuration
cat > k8s/base/loki/loki-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: monitoring
data:
  loki.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
    
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory
    
    schema_config:
      configs:
        - from: 2023-01-01
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
    
    ruler:
      alertmanager_url: http://alertmanager:9093
    
    analytics:
      reporting_enabled: false
EOF

# Create Loki StatefulSet
cat > k8s/base/loki/loki-statefulset.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: monitoring
spec:
  serviceName: loki-headless
  replicas: 1
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.9.0
        args:
          - -config.file=/etc/loki/loki.yaml
        ports:
        - containerPort: 3100
          name: http-metrics
        - containerPort: 9096
          name: grpc
        volumeMounts:
        - name: config
          mountPath: /etc/loki
        - name: storage
          mountPath: /loki
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 1
            memory: 2Gi
        livenessProbe:
          httpGet:
            path: /ready
            port: http-metrics
          initialDelaySeconds: 45
        readinessProbe:
          httpGet:
            path: /ready
            port: http-metrics
          initialDelaySeconds: 45
      volumes:
      - name: config
        configMap:
          name: loki-config
  volumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
EOF

# Create Loki Service
cat > k8s/base/loki/loki-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: monitoring
spec:
  type: ClusterIP
  ports:
  - port: 3100
    targetPort: 3100
    name: http-metrics
  selector:
    app: loki
---
apiVersion: v1
kind: Service
metadata:
  name: loki-headless
  namespace: monitoring
spec:
  clusterIP: None
  ports:
  - port: 3100
    targetPort: 3100
    name: http-metrics
  selector:
    app: loki
EOF

# Apply Loki configuration
kubectl apply -f k8s/base/loki/
```

### Day 2-3: Promtail DaemonSet

#### Task ODIN-035: Deploy Promtail
```bash
# Create Promtail configuration
cat > k8s/base/promtail/promtail-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: monitoring
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
    
    positions:
      filename: /tmp/positions.yaml
    
    clients:
      - url: http://loki:3100/loki/api/v1/push
    
    scrape_configs:
    - job_name: system
      static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
    
    - job_name: pods
      kubernetes_sd_configs:
      - role: pod
      pipeline_stages:
      - docker: {}
      relabel_configs:
      - source_labels:
          - __meta_kubernetes_pod_node_name
        target_label: __host__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - action: replace
        replacement: $1
        separator: /
        source_labels:
          - __meta_kubernetes_namespace
          - __meta_kubernetes_pod_name
        target_label: job
      - action: replace
        source_labels:
          - __meta_kubernetes_namespace
        target_label: namespace
      - action: replace
        source_labels:
          - __meta_kubernetes_pod_name
        target_label: pod
      - action: replace
        source_labels:
          - __meta_kubernetes_pod_container_name
        target_label: container
      - replacement: /var/log/pods/*$1/*.log
        separator: /
        source_labels:
          - __meta_kubernetes_pod_uid
          - __meta_kubernetes_pod_container_name
        target_label: __path__
EOF

# Create Promtail DaemonSet
cat > k8s/base/promtail/promtail-daemonset.yaml << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: monitoring
spec:
  selector:
    matchLabels:
      name: promtail
  template:
    metadata:
      labels:
        name: promtail
    spec:
      serviceAccountName: promtail
      containers:
      - name: promtail
        image: grafana/promtail:2.9.0
        args:
          - -config.file=/etc/promtail/promtail.yaml
        env:
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        ports:
        - containerPort: 9080
          name: http-metrics
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
EOF

# Create Promtail RBAC
cat > k8s/base/promtail/promtail-rbac.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: promtail
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: promtail
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: promtail
subjects:
- kind: ServiceAccount
  name: promtail
  namespace: monitoring
EOF

# Apply Promtail configuration
kubectl apply -f k8s/base/promtail/
```

### Day 4-5: Log Integration and Dashboards

#### Task ODIN-037: Configure Loki in Grafana
```bash
# Add Loki datasource to Grafana
cat > k8s/base/grafana/loki-datasource.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-loki
  namespace: monitoring
data:
  loki-datasource.yaml: |
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki:3100
      jsonData:
        timeout: 60
        maxLines: 1000
      editable: true
EOF

# Create Logs Dashboard
cat > monitoring/dashboards/logs-dashboard.json << 'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": "Loki",
      "fieldConfig": {
        "defaults": {},
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 24,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "options": {
        "showLabels": false,
        "showCommonLabels": false,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": false,
        "showAbsoluteTime": false,
        "prettifyLogMessage": false,
        "enableLogDetails": true,
        "dedupStrategy": "none"
      },
      "targets": [
        {
          "expr": "{namespace=\"monitoring\"}",
          "refId": "A"
        }
      ],
      "title": "Monitoring Namespace Logs",
      "type": "logs"
    },
    {
      "datasource": "Loki",
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          },
          "unit": "short"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 8
      },
      "id": 4,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "text": {},
        "textMode": "auto"
      },
      "pluginVersion": "8.0.0",
      "targets": [
        {
          "expr": "sum(rate({namespace=\"monitoring\"}[5m])) by (pod)",
          "refId": "A"
        }
      ],
      "title": "Log Rate by Pod",
      "type": "stat"
    }
  ],
  "schemaVersion": 27,
  "style": "dark",
  "tags": ["logs"],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Logs Overview",
  "uid": "logs-overview",
  "version": 0
}
EOF

# Apply updates
kubectl apply -f k8s/base/grafana/loki-datasource.yaml
kubectl rollout restart deployment/grafana -n monitoring
```

## Sprint 6: Alerting Configuration (Week 6)

### Day 6-7: AlertManager Deployment

#### Task ODIN-041: Deploy AlertManager
```bash
# Create AlertManager configuration
cat > k8s/base/alertmanager/alertmanager-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m
    
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default-receiver'
      routes:
      - match:
          severity: critical
        receiver: critical-receiver
      - match:
          alertname: GPUHighTemperature
        receiver: gpu-alerts
    
    receivers:
    - name: 'default-receiver'
      webhook_configs:
      - url: 'http://webhook-receiver:5001/'
        send_resolved: true
    
    - name: 'critical-receiver'
      webhook_configs:
      - url: 'http://webhook-receiver:5001/critical'
        send_resolved: true
    
    - name: 'gpu-alerts'
      webhook_configs:
      - url: 'http://webhook-receiver:5001/gpu'
        send_resolved: true
    
    inhibit_rules:
    - source_match:
        severity: 'critical'
      target_match:
        severity: 'warning'
      equal: ['alertname', 'dev', 'instance']
EOF

# Create AlertManager Deployment
cat > k8s/base/alertmanager/alertmanager-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      containers:
      - name: alertmanager
        image: prom/alertmanager:v0.25.0
        args:
          - '--config.file=/etc/alertmanager/alertmanager.yml'
          - '--storage.path=/alertmanager'
        ports:
        - containerPort: 9093
        volumeMounts:
        - name: config
          mountPath: /etc/alertmanager
        - name: storage
          mountPath: /alertmanager
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
      volumes:
      - name: config
        configMap:
          name: alertmanager-config
      - name: storage
        persistentVolumeClaim:
          claimName: alertmanager-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  selector:
    app: alertmanager
  ports:
  - port: 9093
    targetPort: 9093
EOF

# Create PVC for AlertManager
cat > k8s/base/alertmanager/alertmanager-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: alertmanager-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Apply AlertManager configuration
kubectl apply -f k8s/base/alertmanager/
```

### Day 8-9: Alert Rules Configuration

#### Task ODIN-043 & ODIN-044: Create Alert Rules
```bash
# Create Prometheus Alert Rules
cat > k8s/base/prometheus/alert-rules.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alert-rules
  namespace: monitoring
data:
  alert-rules.yml: |
    groups:
    - name: system-alerts
      interval: 30s
      rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% (current value: {{ $value }}%)"
      
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% (current value: {{ $value }}%)"
      
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space"
          description: "Disk space is below 15% (current value: {{ $value }}%)"
    
    - name: gpu-alerts
      interval: 30s
      rules:
      - alert: GPUHighTemperature
        expr: DCGM_FI_DEV_GPU_TEMP > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "GPU temperature high"
          description: "GPU {{ $labels.gpu }} temperature is {{ $value }}°C"
      
      - alert: GPUMemoryFull
        expr: (DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)) * 100 > 95
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GPU memory almost full"
          description: "GPU {{ $labels.gpu }} memory usage is {{ $value }}%"
      
      - alert: GPUPowerHigh
        expr: DCGM_FI_DEV_POWER_USAGE > 350
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GPU power consumption high"
          description: "GPU {{ $labels.gpu }} power usage is {{ $value }}W"
    
    - name: monitoring-alerts
      interval: 30s
      rules:
      - alert: PrometheusDown
        expr: up{job="prometheus"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Prometheus is down"
          description: "Prometheus has been down for more than 1 minute"
      
      - alert: ExporterDown
        expr: up == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Exporter is down"
          description: "{{ $labels.job }} exporter is down"
EOF

# Update Prometheus configuration to include alert rules
kubectl create configmap prometheus-alert-rules --from-file=k8s/base/prometheus/alert-rules.yml -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Reload Prometheus configuration
kubectl rollout restart deployment/prometheus -n monitoring
```

### Day 9-10: Testing and Validation

#### Test Alert Firing
```bash
# Create test pod to trigger alerts
cat > tests/alert-test.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stress-test
  namespace: monitoring
spec:
  containers:
  - name: stress
    image: progrium/stress
    args:
      - --cpu
      - "2"
      - --timeout
      - "300s"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 2000m
        memory: 512Mi
EOF

# Run stress test to trigger CPU alert
kubectl apply -f tests/alert-test.yaml

# Monitor alert status
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {alertname: .labels.alertname, state: .state}'

# Check AlertManager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093 &
curl http://localhost:9093/api/v1/alerts | jq '.[] | {alertname: .labels.alertname, status: .status}'

# Clean up test pod
kubectl delete pod stress-test -n monitoring
```

## Validation Tests

### Logging Validation
```python
# tests/test_logging.py
import subprocess
import json
import time

def test_loki_health():
    """Test Loki is healthy"""
    result = subprocess.run(
        ['kubectl', 'get', 'pod', '-n', 'monitoring', '-l', 'app=loki', 
         '-o', 'jsonpath={.items[0].status.conditions[?(@.type=="Ready")].status}'],
        capture_output=True, text=True
    )
    assert result.stdout == "True", "Loki pod is not ready"

def test_promtail_running():
    """Test Promtail is running on all nodes"""
    nodes_result = subprocess.run(
        ['kubectl', 'get', 'nodes', '-o', 'json'],
        capture_output=True, text=True
    )
    node_count = len(json.loads(nodes_result.stdout)['items'])
    
    promtail_result = subprocess.run(
        ['kubectl', 'get', 'pods', '-n', 'monitoring', '-l', 'name=promtail', 
         '-o', 'json'],
        capture_output=True, text=True
    )
    promtail_count = len(json.loads(promtail_result.stdout)['items'])
    
    assert promtail_count == node_count, f"Promtail not running on all nodes: {promtail_count}/{node_count}"

def test_log_ingestion():
    """Test logs are being ingested"""
    # Create a test log
    subprocess.run([
        'kubectl', 'run', 'test-logger', '--image=busybox', 
        '--restart=Never', '--', 'sh', '-c', 
        'echo "TEST_LOG_ENTRY_12345" && sleep 30'
    ])
    
    # Wait for log ingestion
    time.sleep(10)
    
    # Query Loki for the test log
    result = subprocess.run([
        'kubectl', 'exec', '-n', 'monitoring', 'deployment/grafana', '--',
        'curl', '-s', 'http://loki:3100/loki/api/v1/query',
        '-G', '--data-urlencode', 'query={job="pods"} |= "TEST_LOG_ENTRY_12345"'
    ], capture_output=True, text=True)
    
    # Clean up
    subprocess.run(['kubectl', 'delete', 'pod', 'test-logger', '--ignore-not-found'])
    
    assert "TEST_LOG_ENTRY_12345" in result.stdout, "Test log not found in Loki"
```

### Alerting Validation
```bash
# Verify all alert rules are loaded
kubectl exec -n monitoring deployment/prometheus -- promtool check rules /etc/prometheus/alert-rules.yml

# Check AlertManager configuration
kubectl exec -n monitoring deployment/alertmanager -- amtool check-config /etc/alertmanager/alertmanager.yml
```

## Deliverables Checklist

### Logging Stack
- [ ] Loki deployed with persistence
- [ ] Promtail running on all nodes
- [ ] Log parsing configured
- [ ] Loki datasource in Grafana
- [ ] Logs dashboard created
- [ ] Log retention configured

### Alerting Stack
- [ ] AlertManager deployed
- [ ] Alert rules configured
- [ ] Notification channels setup
- [ ] Alert routing working
- [ ] GPU alerts configured
- [ ] Test alerts validated

### Integration
- [ ] Logs searchable in Grafana
- [ ] Alerts visible in Prometheus
- [ ] AlertManager receiving alerts
- [ ] Log-based alerts possible
- [ ] Metrics and logs correlated

## Success Criteria
1. Logs from all pods visible in Grafana
2. Log search returns results within 2 seconds
3. Alerts fire within configured thresholds
4. AlertManager routes alerts correctly
5. GPU temperature alerts working
6. No log data loss over 24 hours

## Troubleshooting Guide

### Common Issues

1. **Loki not receiving logs**
   ```bash
   # Check Promtail logs
   kubectl logs -n monitoring daemonset/promtail
   # Verify Promtail can reach Loki
   kubectl exec -n monitoring daemonset/promtail -- wget -O- http://loki:3100/ready
   ```

2. **Alerts not firing**
   ```bash
   # Check Prometheus configuration
   kubectl logs -n monitoring deployment/prometheus | grep "error"
   # Verify alert rules syntax
   kubectl exec -n monitoring deployment/prometheus -- promtool check rules /etc/prometheus/alert-rules.yml
   ```

3. **AlertManager not receiving alerts**
   ```bash
   # Check Prometheus can reach AlertManager
   kubectl exec -n monitoring deployment/prometheus -- wget -O- http://alertmanager:9093/-/healthy
   # Check AlertManager logs
   kubectl logs -n monitoring deployment/alertmanager
   ```

## Claude Execution Notes

All commands in this phase can be executed without sudo. Key points for Claude:

1. Use `kubectl apply` for all deployments
2. ConfigMaps can be created/updated without admin privileges
3. Port forwarding for testing doesn't require sudo
4. Log queries can be done via kubectl exec
5. All validation can be performed with standard kubectl commands

## Next Phase Prerequisites
- Logs successfully ingested for 24+ hours
- All alert rules evaluated without errors
- AlertManager successfully routing test alerts
- Team trained on log queries and alert management
- Backup of Loki data completed
