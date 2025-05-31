# Phase 4: Advanced Features Implementation Plan

## Overview
Phase 4 implements advanced monitoring features including service mesh integration, distributed tracing, and custom exporters. All deployments are designed for Claude to execute without requiring sudo privileges.

## Prerequisites from Phase 3
- [ ] Loki and Promtail operational
- [ ] AlertManager configured and routing alerts
- [ ] Log dashboards functional
- [ ] Alert rules tested and validated

## Sprint 7: Service Mesh and Tracing (Week 7)

### Day 1-2: Service Mesh Evaluation and Installation

#### Task ODIN-049: Evaluate Service Mesh Options
```bash
# Create comparison matrix
cat > docs/service-mesh-comparison.md << 'EOF'
# Service Mesh Comparison for ODIN

## Linkerd (Recommended for ODIN)
- **Pros**: Lightweight, easy to install, minimal resource usage
- **Cons**: Fewer features than Istio
- **Resource Usage**: ~50MB per proxy
- **GPU Compatibility**: Excellent

## Istio
- **Pros**: Feature-rich, industry standard
- **Cons**: Complex, resource-intensive
- **Resource Usage**: ~150MB per proxy
- **GPU Compatibility**: Good with configuration

## Decision: Linkerd for development environment
EOF

# Install Linkerd CLI (for Claude to use)
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Verify installation
linkerd version --client
```

#### Task ODIN-050: Deploy Linkerd
```bash
# Check cluster readiness
linkerd check --pre

# Install Linkerd control plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Wait for control plane to be ready
linkerd check

# Install Linkerd Viz extension for observability
linkerd viz install | kubectl apply -f -

# Create ServiceProfile for monitoring services
cat > k8s/base/linkerd/service-profiles.yaml << 'EOF'
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: prometheus
  namespace: monitoring
spec:
  routes:
  - name: query
    condition:
      method: GET
      pathRegex: "/api/v1/query.*"
  - name: query_range
    condition:
      method: GET
      pathRegex: "/api/v1/query_range.*"
  retryBudget:
    retryRatio: 0.2
    minRetriesPerSecond: 10
    ttl: 10s
---
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: grafana
  namespace: monitoring
spec:
  routes:
  - name: api
    condition:
      pathRegex: "/api/.*"
  - name: dashboards
    condition:
      pathRegex: "/d/.*"
  retryBudget:
    retryRatio: 0.2
    minRetriesPerSecond: 10
    ttl: 10s
EOF

# Apply service profiles
kubectl apply -f k8s/base/linkerd/service-profiles.yaml
```

### Day 2-3: Inject Service Mesh

#### Task ODIN-051: Configure Mesh Observability
```bash
# Inject Linkerd into monitoring namespace
kubectl get deploy -n monitoring -o yaml | linkerd inject - | kubectl apply -f -

# Verify injection
linkerd check --proxy -n monitoring

# Create Linkerd dashboard access
cat > k8s/base/linkerd/linkerd-viz-ingress.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: linkerd-viz
  namespace: linkerd-viz
spec:
  type: NodePort
  ports:
  - port: 8084
    targetPort: 8084
    nodePort: 30084
  selector:
    component: web
EOF

kubectl apply -f k8s/base/linkerd/linkerd-viz-ingress.yaml

# Configure Prometheus to scrape Linkerd metrics
cat > k8s/base/prometheus/linkerd-scrape-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-linkerd-config
  namespace: monitoring
data:
  linkerd-prometheus.yml: |
    - job_name: 'linkerd-controller'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: ['linkerd', 'linkerd-viz']
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_container_port_name]
        action: keep
        regex: admin-http
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: replace
        target_label: component

    - job_name: 'linkerd-proxy'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: keep
        regex: linkerd-proxy
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+)(?::\d+)?
        replacement: $1:4191
        target_label: __address__
EOF

# Update Prometheus configuration
kubectl apply -f k8s/base/prometheus/linkerd-scrape-config.yaml
kubectl rollout restart deployment/prometheus -n monitoring
```

### Day 4-5: Distributed Tracing

#### Task ODIN-052: Deploy Tempo for Tracing
```bash
# Deploy Tempo (lightweight alternative to Jaeger)
cat > k8s/base/tempo/tempo-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: monitoring
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
    
    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
    
    ingester:
      trace_idle_period: 10s
      max_block_bytes: 1_000_000
      max_block_duration: 5m
    
    compactor:
      compaction:
        block_retention: 1h
    
    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/blocks
        wal:
          path: /tmp/tempo/wal
    
    overrides:
      metrics_generator_processors: [service-graphs, span-metrics]
EOF

# Deploy Tempo
cat > k8s/base/tempo/tempo-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.2.0
        args:
          - -config.file=/etc/tempo/tempo.yaml
        ports:
        - containerPort: 3200
          name: http
        - containerPort: 4317
          name: otlp-grpc
        - containerPort: 4318
          name: otlp-http
        volumeMounts:
        - name: config
          mountPath: /etc/tempo
        - name: storage
          mountPath: /tmp/tempo
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
      volumes:
      - name: config
        configMap:
          name: tempo-config
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: monitoring
spec:
  selector:
    app: tempo
  ports:
  - name: http
    port: 3200
    targetPort: 3200
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
EOF

kubectl apply -f k8s/base/tempo/
```

#### Task ODIN-053: Configure Trace Collection
```bash
# Add Tempo datasource to Grafana
cat > k8s/base/grafana/tempo-datasource.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-tempo
  namespace: monitoring
data:
  tempo-datasource.yaml: |
    apiVersion: 1
    datasources:
    - name: Tempo
      type: tempo
      access: proxy
      url: http://tempo:3200
      editable: true
      jsonData:
        httpMethod: GET
        tracesToLogs:
          datasourceUid: loki
          mapTagNamesEnabled: true
          mappedTags:
            - key: service.name
              value: service
        serviceMap:
          datasourceUid: prometheus
        nodeGraph:
          enabled: true
EOF

# Apply Tempo datasource
kubectl apply -f k8s/base/grafana/tempo-datasource.yaml
kubectl rollout restart deployment/grafana -n monitoring

# Deploy OpenTelemetry Collector for trace collection
cat > k8s/base/otel/otel-collector.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: monitoring
data:
  otel-collector-config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      batch:
        timeout: 1s
      memory_limiter:
        limit_mib: 512
        spike_limit_mib: 128
        check_interval: 1s
    
    exporters:
      tempo:
        endpoint: tempo:4317
        tls:
          insecure: true
      prometheus:
        endpoint: "0.0.0.0:8889"
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [tempo]
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [prometheus]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
      - name: otel-collector
        image: otel/opentelemetry-collector-contrib:0.81.0
        args:
          - --config=/etc/otel-collector-config.yaml
        ports:
        - containerPort: 4317
          name: otlp-grpc
        - containerPort: 4318
          name: otlp-http
        - containerPort: 8889
          name: prometheus
        volumeMounts:
        - name: config
          mountPath: /etc/otel-collector-config.yaml
          subPath: otel-collector-config.yaml
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
          name: otel-collector-config
EOF

kubectl apply -f k8s/base/otel/
```

## Sprint 8: Custom Exporters and Advanced Monitoring (Week 8)

### Day 6-7: Custom Exporters Development

#### Task ODIN-057: Develop Custom Exporters
```bash
# Create custom exporter for application metrics
cat > k8s/base/exporters/custom-exporter.py << 'EOF'
#!/usr/bin/env python3
import time
import os
from prometheus_client import start_http_server, Gauge, Counter, Histogram, Summary
import random

# Custom metrics
gpu_job_queue = Gauge('gpu_job_queue_length', 'Number of jobs waiting for GPU')
gpu_job_duration = Histogram('gpu_job_duration_seconds', 'GPU job duration in seconds')
ml_model_inference_time = Summary('ml_model_inference_seconds', 'ML model inference time')
ml_model_accuracy = Gauge('ml_model_accuracy', 'Current ML model accuracy', ['model_name'])
api_requests = Counter('api_requests_total', 'Total API requests', ['method', 'endpoint'])

def collect_custom_metrics():
    """Simulate collecting custom metrics"""
    while True:
        # Simulate GPU job queue
        gpu_job_queue.set(random.randint(0, 20))
        
        # Simulate GPU job completion
        gpu_job_duration.observe(random.uniform(10, 300))
        
        # Simulate ML inference
        ml_model_inference_time.observe(random.uniform(0.1, 2.0))
        
        # Simulate model accuracy
        ml_model_accuracy.labels(model_name='resnet50').set(random.uniform(0.85, 0.99))
        ml_model_accuracy.labels(model_name='bert').set(random.uniform(0.80, 0.95))
        
        # Simulate API requests
        api_requests.labels(method='GET', endpoint='/api/v1/predict').inc()
        api_requests.labels(method='POST', endpoint='/api/v1/train').inc()
        
        time.sleep(15)

if __name__ == '__main__':
    # Start Prometheus metrics server
    start_http_server(8000)
    print("Custom exporter started on port 8000")
    collect_custom_metrics()
EOF

# Create Dockerfile for custom exporter
cat > k8s/base/exporters/Dockerfile.custom-exporter << 'EOF'
FROM python:3.11-slim
RUN pip install prometheus-client
COPY custom-exporter.py /app/
WORKDIR /app
CMD ["python", "custom-exporter.py"]
EOF

# Create deployment for custom exporter
cat > k8s/base/exporters/custom-exporter-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: custom-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: custom-exporter
  template:
    metadata:
      labels:
        app: custom-exporter
    spec:
      containers:
      - name: custom-exporter
        image: python:3.11-slim
        command: ["sh", "-c"]
        args:
          - |
            pip install prometheus-client
            cat > /app/custom-exporter.py << 'EOL'
            import time
            import random
            from prometheus_client import start_http_server, Gauge, Counter, Histogram, Summary
            
            gpu_job_queue = Gauge('gpu_job_queue_length', 'Number of jobs waiting for GPU')
            gpu_job_duration = Histogram('gpu_job_duration_seconds', 'GPU job duration in seconds')
            ml_model_inference_time = Summary('ml_model_inference_seconds', 'ML model inference time')
            ml_model_accuracy = Gauge('ml_model_accuracy', 'Current ML model accuracy', ['model_name'])
            api_requests = Counter('api_requests_total', 'Total API requests', ['method', 'endpoint'])
            
            def collect_custom_metrics():
                while True:
                    gpu_job_queue.set(random.randint(0, 20))
                    gpu_job_duration.observe(random.uniform(10, 300))
                    ml_model_inference_time.observe(random.uniform(0.1, 2.0))
                    ml_model_accuracy.labels(model_name='resnet50').set(random.uniform(0.85, 0.99))
                    ml_model_accuracy.labels(model_name='bert').set(random.uniform(0.80, 0.95))
                    api_requests.labels(method='GET', endpoint='/api/v1/predict').inc()
                    api_requests.labels(method='POST', endpoint='/api/v1/train').inc()
                    time.sleep(15)
            
            if __name__ == '__main__':
                start_http_server(8000)
                print("Custom exporter started on port 8000")
                collect_custom_metrics()
            EOL
            python /app/custom-exporter.py
        ports:
        - containerPort: 8000
          name: metrics
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: custom-exporter
  namespace: monitoring
  labels:
    app: custom-exporter
spec:
  selector:
    app: custom-exporter
  ports:
  - port: 8000
    targetPort: 8000
    name: metrics
EOF

kubectl apply -f k8s/base/exporters/custom-exporter-deployment.yaml

# Update Prometheus to scrape custom exporter
kubectl edit configmap prometheus-config -n monitoring
# Add the following job:
# - job_name: 'custom-exporter'
#   static_configs:
#   - targets: ['custom-exporter:8000']
```

### Day 7-8: SLI/SLO Implementation

#### Task ODIN-055: Implement SLI/SLO Tracking
```bash
# Create SLO rules for Prometheus
cat > k8s/base/prometheus/slo-rules.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-slo-rules
  namespace: monitoring
data:
  slo-rules.yml: |
    groups:
    - name: slo-rules
      interval: 30s
      rules:
      # API Availability SLO
      - record: slo:api_availability:ratio_rate5m
        expr: |
          sum(rate(api_requests_total{status!~"5.."}[5m])) /
          sum(rate(api_requests_total[5m]))
      
      # GPU Utilization SLO
      - record: slo:gpu_utilization:ratio_rate5m
        expr: |
          avg(avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m]))
      
      # Response Time SLO
      - record: slo:response_time:p99_5m
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
          )
      
      # Error Budget
      - alert: ErrorBudgetBurn
        expr: |
          (
            1 - slo:api_availability:ratio_rate5m
          ) > (1 - 0.99) * 1.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Error budget burn rate is high"
          description: "Error rate is {{ $value | humanizePercentage }} which is burning error budget"
EOF

# Create SLO Dashboard
cat > monitoring/dashboards/slo-dashboard.json << 'EOF'
{
  "dashboard": {
    "title": "SLO Dashboard",
    "panels": [
      {
        "title": "API Availability SLO",
        "targets": [
          {
            "expr": "slo:api_availability:ratio_rate5m * 100",
            "legendFormat": "Current"
          },
          {
            "expr": "99",
            "legendFormat": "Target"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "type": "graph",
        "yaxes": [{"format": "percent", "min": 95, "max": 100}]
      },
      {
        "title": "GPU Utilization",
        "targets": [
          {
            "expr": "slo:gpu_utilization:ratio_rate5m",
            "legendFormat": "GPU {{ gpu }}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "type": "graph",
        "yaxes": [{"format": "percent", "min": 0, "max": 100}]
      },
      {
        "title": "Response Time P99",
        "targets": [
          {
            "expr": "slo:response_time:p99_5m",
            "legendFormat": "P99 Latency"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "type": "graph",
        "yaxes": [{"format": "s"}]
      },
      {
        "title": "Error Budget Remaining",
        "targets": [
          {
            "expr": "(1 - (1 - slo:api_availability:ratio_rate5m) / (1 - 0.99)) * 100",
            "legendFormat": "Remaining Budget"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "type": "graph",
        "yaxes": [{"format": "percent", "min": 0, "max": 100}]
      }
    ],
    "time": {"from": "now-24h", "to": "now"},
    "uid": "slo-dashboard",
    "version": 1
  }
}
EOF

kubectl create configmap prometheus-slo-rules --from-file=k8s/base/prometheus/slo-rules.yml -n monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/prometheus -n monitoring
```

### Day 9-10: Backup and Recovery Implementation

#### Task ODIN-059: Implement Automated Backups
```bash
# Create backup script
cat > scripts/backup-monitoring.sh << 'EOF'
#!/bin/bash
# ODIN Monitoring Backup Script - No sudo required

set -e

BACKUP_DIR="${HOME}/odin-backups/$(date +%Y%m%d-%H%M%S)"
NAMESPACE="monitoring"

echo "Starting ODIN backup to ${BACKUP_DIR}..."
mkdir -p "${BACKUP_DIR}"

# Backup Prometheus data
echo "Backing up Prometheus data..."
kubectl exec -n ${NAMESPACE} deployment/prometheus -- tar czf - /prometheus | tar xzf - -C "${BACKUP_DIR}"

# Backup Grafana data
echo "Backing up Grafana data..."
kubectl exec -n ${NAMESPACE} deployment/grafana -- tar czf - /var/lib/grafana | tar xzf - -C "${BACKUP_DIR}"

# Backup Loki data
echo "Backing up Loki data..."
kubectl exec -n ${NAMESPACE} statefulset/loki -- tar czf - /loki | tar xzf - -C "${BACKUP_DIR}"

# Backup configurations
echo "Backing up configurations..."
mkdir -p "${BACKUP_DIR}/configs"
kubectl get configmaps -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/configs/configmaps.yaml"
kubectl get secrets -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/configs/secrets.yaml"

# Create backup metadata
cat > "${BACKUP_DIR}/metadata.json" << EOL
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "namespace": "${NAMESPACE}",
  "components": ["prometheus", "grafana", "loki"],
  "size": "$(du -sh ${BACKUP_DIR} | cut -f1)"
}
EOL

echo "Backup completed: ${BACKUP_DIR}"

# Cleanup old backups (keep last 7)
find "${HOME}/odin-backups" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
EOF

chmod +x scripts/backup-monitoring.sh

# Create restore script
cat > scripts/restore-monitoring.sh << 'EOF'
#!/bin/bash
# ODIN Monitoring Restore Script - No sudo required

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-directory>"
    exit 1
fi

BACKUP_DIR="$1"
NAMESPACE="monitoring"

if [ ! -d "${BACKUP_DIR}" ]; then
    echo "Error: Backup directory ${BACKUP_DIR} does not exist"
    exit 1
fi

echo "Starting ODIN restore from ${BACKUP_DIR}..."

# Scale down deployments
echo "Scaling down deployments..."
kubectl scale deployment --all -n ${NAMESPACE} --replicas=0
kubectl scale statefulset --all -n ${NAMESPACE} --replicas=0

# Wait for pods to terminate
sleep 30

# Restore configurations
echo "Restoring configurations..."
kubectl apply -f "${BACKUP_DIR}/configs/configmaps.yaml"
kubectl apply -f "${BACKUP_DIR}/configs/secrets.yaml"

# Restore Prometheus data
echo "Restoring Prometheus data..."
kubectl exec -n ${NAMESPACE} deployment/prometheus -- rm -rf /prometheus/*
cat "${BACKUP_DIR}/prometheus.tar.gz" | kubectl exec -i -n ${NAMESPACE} deployment/prometheus -- tar xzf - -C /

# Restore Grafana data
echo "Restoring Grafana data..."
kubectl exec -n ${NAMESPACE} deployment/grafana -- rm -rf /var/lib/grafana/*
cat "${BACKUP_DIR}/grafana.tar.gz" | kubectl exec -i -n ${NAMESPACE} deployment/grafana -- tar xzf - -C /

# Restore Loki data
echo "Restoring Loki data..."
kubectl exec -n ${NAMESPACE} statefulset/loki -- rm -rf /loki/*
cat "${BACKUP_DIR}/loki.tar.gz" | kubectl exec -i -n ${NAMESPACE} statefulset/loki -- tar xzf - -C /

# Scale up deployments
echo "Scaling up deployments..."
kubectl scale deployment --all -n ${NAMESPACE} --replicas=1
kubectl scale statefulset --all -n ${NAMESPACE} --replicas=1

echo "Restore completed from ${BACKUP_DIR}"
EOF

chmod +x scripts/restore-monitoring.sh

# Create CronJob for automated backups
cat > k8s/base/backup/backup-cronjob.yaml << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: monitoring-backup
  namespace: monitoring
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              # Backup script inline
              BACKUP_DIR="/backups/$(date +%Y%m%d-%H%M%S)"
              mkdir -p "${BACKUP_DIR}"
              
              # Backup Prometheus
              kubectl exec deployment/prometheus -- tar czf - /prometheus > "${BACKUP_DIR}/prometheus.tar.gz"
              
              # Backup Grafana
              kubectl exec deployment/grafana -- tar czf - /var/lib/grafana > "${BACKUP_DIR}/grafana.tar.gz"
              
              # Backup Loki
              kubectl exec statefulset/loki -- tar czf - /loki > "${BACKUP_DIR}/loki.tar.gz"
              
              # Backup configs
              kubectl get configmaps -o yaml > "${BACKUP_DIR}/configmaps.yaml"
              kubectl get secrets -o yaml > "${BACKUP_DIR}/secrets.yaml"
              
              echo "Backup completed: ${BACKUP_DIR}"
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
EOF

kubectl apply -f k8s/base/backup/backup-cronjob.yaml
```

## Validation Tests

### Service Mesh Validation
```python
# tests/test_service_mesh.py
import subprocess
import json
import requests

def test_linkerd_installed():
    """Test Linkerd is installed"""
    result = subprocess.run(['linkerd', 'check'], capture_output=True, text=True)
    assert result.returncode == 0, "Linkerd check failed"

def test_monitoring_meshed():
    """Test monitoring namespace is meshed"""
    result = subprocess.run(
        ['kubectl', 'get', 'pods', '-n', 'monitoring', '-o', 'json'],
        capture_output=True, text=True
    )
    pods = json.loads(result.stdout)['items']
    
    for pod in pods:
        containers = [c['name'] for c in pod['spec']['containers']]
        assert 'linkerd-proxy' in containers, f"Pod {pod['metadata']['name']} not meshed"

def test_service_profiles():
    """Test service profiles are created"""
    result = subprocess.run(
        ['kubectl', 'get', 'serviceprofiles', '-n', 'monitoring'],
        capture_output=True, text=True
    )
    assert 'prometheus' in result.stdout
    assert 'grafana' in result.stdout
```

### Tracing Validation
```bash
# Test trace collection
kubectl run trace-test --rm -it --image=curlimages/curl -- \
  curl -X POST http://otel-collector.monitoring:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "test-service"}}]},
      "scopeSpans": [{
        "spans": [{
          "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
          "spanId": "051e64f5b8c54c99",
          "name": "test-span",
          "startTimeUnixNano": "'$(date +%s)'000000000",
          "endTimeUnixNano": "'$(date +%s)'000000001"
        }]
      }]
    }]
  }'

# Query Tempo for the trace
kubectl exec -n monitoring deployment/grafana -- \
  curl -s "http://tempo:3200/api/traces/5b8aa5a2d2c872e8321cf37308d69df2"
```

### Custom Metrics Validation
```bash
# Check custom exporter metrics
kubectl port-forward -n monitoring svc/custom-exporter 8000:8000 &
curl -s http://localhost:8000/metrics | grep -E "(gpu_job_queue_length|ml_model_accuracy)"

# Query custom metrics in Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s "http://localhost:9090/api/v1/query?query=gpu_job_queue_length" | jq '.data.result'
```

## Deliverables Checklist

### Service Mesh
- [ ] Linkerd control plane installed
- [ ] Monitoring namespace meshed
- [ ] Service profiles created
- [ ] Linkerd metrics in Prometheus
- [ ] Service mesh dashboard in Grafana

### Tracing
- [ ] Tempo deployed and operational
- [ ] OpenTelemetry collector running
- [ ] Traces visible in Grafana
- [ ] Trace to logs correlation working
- [ ] Service dependency graph available

### Custom Monitoring
- [ ] Custom exporter deployed
- [ ] Business metrics collected
- [ ] SLO rules configured
- [ ] SLO dashboard created
- [ ] Error budget tracking

### Backup & Recovery
- [ ] Backup scripts created
- [ ] Restore scripts tested
- [ ] Automated backup CronJob
- [ ] Backup retention policy
- [ ] Recovery procedures documented

## Success Criteria
1. All services show in Linkerd dashboard
2. Traces collected and queryable within 30s
3. Custom metrics available in Prometheus
4. SLO dashboard shows all key metrics
5. Backup completes in < 5 minutes
6. Restore tested and working

## Troubleshooting Guide

### Common Issues

1. **Linkerd injection failing**
   ```bash
   # Check webhook
   kubectl get mutatingwebhookconfigurations
   # Restart deployment
   kubectl rollout restart deployment/<name> -n monitoring
   ```

2. **No traces in Tempo**
   ```bash
   # Check OTEL collector logs
   kubectl logs -n monitoring daemonset/otel-collector
   # Verify Tempo is receiving data
   kubectl logs -n monitoring deployment/tempo | grep "received"
   ```

3. **Custom metrics not appearing**
   ```bash
   # Check exporter endpoint
   kubectl exec -n monitoring deployment/custom-exporter -- curl localhost:8000/metrics
   # Verify Prometheus scrape
   kubectl logs -n monitoring deployment/prometheus | grep custom-exporter
   ```

## Claude Execution Notes

All commands can be executed without sudo:

1. Linkerd CLI installation goes to user home directory
2. All Kubernetes operations use kubectl
3. Port forwarding for testing doesn't require elevated privileges
4. Backup scripts use user's home directory for storage
5. All configurations applied via ConfigMaps

## Next Phase Prerequisites
- Service mesh stable for 24+ hours
- Traces successfully collected
- Custom metrics integrated
- SLO baselines established
- Backup and restore procedures verified