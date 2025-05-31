# Phase 2: Core Monitoring Stack Implementation Plan

## Overview
Phase 2 deploys the core monitoring stack including Prometheus, Grafana, and essential exporters with GPU metrics support.

## Prerequisites from Phase 1
- [ ] K3s cluster with GPU support operational
- [ ] Storage classes configured and tested
- [ ] Monitoring namespace created
- [ ] Helm and Kustomize ready
- [ ] CI/CD pipeline functional

## Sprint 3: Prometheus and Grafana Core (Week 3)

### Day 1-2: Prometheus Deployment
```yaml
# Task ODIN-017: prometheus-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    # Alertmanager configuration
    alerting:
      alertmanagers:
        - static_configs:
            - targets: []
    
    # Scrape configurations
    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
          - targets: ['localhost:9090']
      
      - job_name: 'kubernetes-apiservers'
        kubernetes_sd_configs:
          - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
            action: keep
            regex: default;kubernetes;https
      
      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v2.45.0
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus/'
          - '--web.console.libraries=/etc/prometheus/console_libraries'
          - '--web.console.templates=/etc/prometheus/consoles'
          - '--web.enable-lifecycle'
          - '--storage.tsdb.retention.time=30d'
          - '--storage.tsdb.retention.size=10GB'
        ports:
        - containerPort: 9090
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2
            memory: 4Gi
        volumeMounts:
        - name: prometheus-config-volume
          mountPath: /etc/prometheus/
        - name: prometheus-storage-volume
          mountPath: /prometheus/
      volumes:
      - name: prometheus-config-volume
        configMap:
          defaultMode: 420
          name: prometheus-config
      - name: prometheus-storage-volume
        persistentVolumeClaim:
          claimName: prometheus-pvc

---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  type: ClusterIP
  ports:
  - port: 9090
    targetPort: 9090
```

### Day 2-3: Grafana Deployment
```yaml
# Task ODIN-020: grafana-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus:9090
      isDefault: true
      jsonData:
        timeInterval: "15s"
      editable: true

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.0.0
        ports:
        - containerPort: 3000
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 1
            memory: 1Gi
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: grafana-secret
              key: admin-password
        - name: GF_INSTALL_PLUGINS
          value: grafana-clock-panel,grafana-simple-json-datasource,grafana-piechart-panel
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        - name: grafana-datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: grafana-dashboards
          mountPath: /etc/grafana/provisioning/dashboards
        - name: dashboards-config
          mountPath: /var/lib/grafana/dashboards
      volumes:
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: grafana-pvc
      - name: grafana-datasources
        configMap:
          name: grafana-datasources
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboard-provider
      - name: dashboards-config
        configMap:
          name: grafana-dashboards

---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  type: NodePort
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30300
```

### Day 4-5: Basic Exporters
```yaml
# Task ODIN-022: node-exporter.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostPID: true
      hostIPC: true
      hostNetwork: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.6.0
        args:
          - --path.procfs=/host/proc
          - --path.sysfs=/host/sys
          - --path.rootfs=/host
          - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/pods/.+)($|/)
        ports:
        - containerPort: 9100
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: root
          mountPath: /host
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      - name: root
        hostPath:
          path: /

---
# Task ODIN-023: cadvisor.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cadvisor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: cadvisor
  template:
    metadata:
      labels:
        app: cadvisor
    spec:
      containers:
      - name: cadvisor
        image: gcr.io/cadvisor/cadvisor:v0.47.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 150m
            memory: 200Mi
          limits:
            cpu: 300m
            memory: 400Mi
        volumeMounts:
        - name: rootfs
          mountPath: /rootfs
          readOnly: true
        - name: var-run
          mountPath: /var/run
          readOnly: true
        - name: sys
          mountPath: /sys
          readOnly: true
        - name: docker
          mountPath: /var/lib/docker
          readOnly: true
        - name: disk
          mountPath: /dev/disk
          readOnly: true
        securityContext:
          privileged: true
      volumes:
      - name: rootfs
        hostPath:
          path: /
      - name: var-run
        hostPath:
          path: /var/run
      - name: sys
        hostPath:
          path: /sys
      - name: docker
        hostPath:
          path: /var/lib/docker
      - name: disk
        hostPath:
          path: /dev/disk
```

## Sprint 4: GPU Monitoring and Dashboards (Week 4)

### Day 6-7: NVIDIA DCGM Exporter
```yaml
# Task ODIN-025: nvidia-dcgm-exporter.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-dcgm-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  template:
    metadata:
      labels:
        app: nvidia-dcgm-exporter
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      containers:
      - name: nvidia-dcgm-exporter
        image: nvcr.io/nvidia/k8s/dcgm-exporter:3.1.3-3.1.4-ubuntu22.04
        env:
        - name: DCGM_EXPORTER_LISTEN
          value: ":9400"
        - name: DCGM_EXPORTER_KUBERNETES
          value: "true"
        ports:
        - containerPort: 9400
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
            nvidia.com/gpu: 0  # Doesn't need GPU allocation
        securityContext:
          runAsNonRoot: false
          runAsUser: 0
          capabilities:
            add:
            - SYS_ADMIN
        volumeMounts:
        - name: pod-gpu-resources
          readOnly: true
          mountPath: /var/lib/kubelet/pod-resources
      volumes:
      - name: pod-gpu-resources
        hostPath:
          path: /var/lib/kubelet/pod-resources
          type: Directory

---
apiVersion: v1
kind: Service
metadata:
  name: nvidia-dcgm-exporter
  namespace: monitoring
  labels:
    app: nvidia-dcgm-exporter
spec:
  selector:
    app: nvidia-dcgm-exporter
  ports:
  - port: 9400
    targetPort: 9400
```

### Day 7-8: Dashboard Creation
```json
# Task ODIN-026: GPU Dashboard
# monitoring/dashboards/gpu-dashboard.json
{
  "dashboard": {
    "title": "NVIDIA GPU Metrics",
    "uid": "nvidia-gpu",
    "panels": [
      {
        "title": "GPU Temperature",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_GPU_TEMP",
            "legendFormat": "GPU {{gpu}}"
          }
        ],
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
        "type": "graph"
      },
      {
        "title": "GPU Utilization",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_GPU_UTIL",
            "legendFormat": "GPU {{gpu}}"
          }
        ],
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0},
        "type": "graph"
      },
      {
        "title": "GPU Power Usage",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_POWER_USAGE",
            "legendFormat": "GPU {{gpu}}"
          }
        ],
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0},
        "type": "graph"
      },
      {
        "title": "GPU Memory Used",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_FB_USED",
            "legendFormat": "GPU {{gpu}} Used"
          },
          {
            "expr": "DCGM_FI_DEV_FB_FREE",
            "legendFormat": "GPU {{gpu}} Free"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "type": "graph"
      }
    ]
  }
}
```

### Day 9-10: Integration and Testing

#### Update Prometheus Configuration
```yaml
# Add to prometheus-config ConfigMap
- job_name: 'node-exporter'
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app]
      action: keep
      regex: node-exporter
    - source_labels: [__meta_kubernetes_pod_node_name]
      action: replace
      target_label: node

- job_name: 'cadvisor'
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app]
      action: keep
      regex: cadvisor

- job_name: 'nvidia-dcgm'
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app]
      action: keep
      regex: nvidia-dcgm-exporter
```

## Validation Tests

### Prometheus Health Check
```bash
# Task: Verify Prometheus is running and scraping
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl http://localhost:9090/-/healthy
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

### Grafana Access Test
```python
# tests/test_grafana.py
import requests
import base64

def test_grafana_api():
    """Test Grafana API access"""
    # Get admin password from secret
    password = subprocess.run(
        ['kubectl', 'get', 'secret', 'grafana-secret', '-n', 'monitoring',
         '-o', 'jsonpath={.data.admin-password}'],
        capture_output=True
    ).stdout.decode()
    password = base64.b64decode(password).decode()
    
    # Test API access
    response = requests.get(
        'http://localhost:30300/api/health',
        auth=('admin', password)
    )
    assert response.status_code == 200
    assert response.json()['database'] == 'ok'
```

### GPU Metrics Test
```bash
# Task: Verify GPU metrics are being collected
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -G http://localhost:9090/api/v1/query \
  --data-urlencode 'query=DCGM_FI_DEV_GPU_TEMP' | jq '.data.result'
```

## Deliverables Checklist

### Core Services
- [ ] Prometheus deployed with persistence
- [ ] Grafana deployed with NodePort access
- [ ] Service discovery configured
- [ ] Data retention policies set

### Exporters
- [ ] Node Exporter running on all nodes
- [ ] cAdvisor collecting container metrics
- [ ] NVIDIA DCGM Exporter collecting GPU metrics
- [ ] All exporters visible in Prometheus targets

### Dashboards
- [ ] System overview dashboard imported
- [ ] Container metrics dashboard created
- [ ] GPU metrics dashboard functional
- [ ] Dashboard provisioning automated

### Integration
- [ ] All metrics queryable in Prometheus
- [ ] Grafana connected to Prometheus
- [ ] GPU temperature/utilization visible
- [ ] API access documented

## Success Criteria
1. Prometheus targets page shows all exporters as UP
2. Grafana accessible at http://<node-ip>:30300
3. GPU metrics visible with query: `DCGM_FI_DEV_GPU_TEMP`
4. System metrics visible: CPU, Memory, Disk, Network
5. Container metrics available for all pods
6. Data persists across pod restarts

## Performance Baselines
- Prometheus memory usage: < 2GB
- Grafana response time: < 2s for dashboards
- Metric ingestion rate: > 10k samples/sec
- Query response time: < 500ms for 1h range

## Troubleshooting Guide

### Common Issues
1. **Prometheus targets down**
   - Check service discovery labels
   - Verify network policies
   - Check exporter logs

2. **No GPU metrics**
   - Verify NVIDIA runtime: `kubectl describe node | grep nvidia`
   - Check DCGM exporter logs
   - Test with `nvidia-smi` in pod

3. **Grafana login fails**
   - Check secret: `kubectl get secret grafana-secret -n monitoring`
   - Verify password encoding
   - Check Grafana logs

## Next Phase Prerequisites
- All exporters reporting metrics
- Dashboards loading successfully
- GPU metrics validated
- Team familiar with PromQL queries
- Backup procedures documented
