# ODIN Kubernetes Project Plan for Ubuntu 22.04 with NVIDIA RTX Support

## Project Overview

ODIN (Observability Dashboard for Infrastructure and NVIDIA) is a comprehensive monitoring stack built on Kubernetes that provides full system observability for Ubuntu 22.04 systems with NVIDIA RTX GPUs.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Ubuntu 22.04 Host System                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    K3s Kubernetes Cluster                    │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │                 Monitoring Namespace                  │   │   │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │   │   │
│  │  │  │Prometheus│  │ Grafana  │  │   AlertManager   │  │   │   │
│  │  │  │  :9090   │  │  :3000   │  │     :9093        │  │   │   │
│  │  │  └─────┬────┘  └────┬─────┘  └──────────────────┘  │   │   │
│  │  │        │             │                               │   │   │
│  │  │  ┌─────▼─────────────▼────────────────────────────┐ │   │   │
│  │  │  │          Service Discovery (CoreDNS)           │ │   │   │
│  │  │  └────────────────┬───────────────────────────────┘ │   │   │
│  │  │                   │                                  │   │   │
│  │  │  ┌────────────────▼───────────────────────────────┐ │   │   │
│  │  │  │              Exporters Layer                    │ │   │   │
│  │  │  │ ┌──────────┐ ┌──────────┐ ┌─────────────────┐ │ │   │   │
│  │  │  │ │   Node   │ │  NVIDIA  │ │     cAdvisor    │ │ │   │   │
│  │  │  │ │ Exporter │ │ Exporter │ │ (Container Mon) │ │ │   │   │
│  │  │  │ │  :9100   │ │  :9400   │ │     :8080       │ │ │   │   │
│  │  │  │ └──────────┘ └──────────┘ └─────────────────┘ │ │   │   │
│  │  │  └─────────────────────────────────────────────────┘ │   │   │
│  │  │                                                      │   │   │
│  │  │  ┌─────────────────────────────────────────────────┐ │   │   │
│  │  │  │              Logging Layer                       │ │   │   │
│  │  │  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │ │   │   │
│  │  │  │  │   Loki   │  │ Promtail │  │   Fluentd    │  │ │   │   │
│  │  │  │  │  :3100   │  │  :9080   │  │   :24224     │  │ │   │   │
│  │  │  │  └──────────┘  └──────────┘  └──────────────┘  │ │   │   │
│  │  │  └─────────────────────────────────────────────────┘ │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  │                                                             │   │
│  │  ┌─────────────────────────────────────────────────────┐   │   │
│  │  │          NVIDIA Device Plugin & Runtime              │   │   │
│  │  └─────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┐   │   │
│                                                             │   │   │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │   │   │
│  │ Docker/Containerd │  │ NVIDIA Driver │  │ CUDA Toolkit │  │   │   │
│  └──────────────┘  └──────────────┘  └─────────────────┘      │   │
└─────────────────────────────────────────────────────────────────┘
```

## Component Communication Matrix

| Source Component | Target Component | Protocol | Port | Purpose |
|-----------------|------------------|----------|------|---------|
| Prometheus | Node Exporter | HTTP | 9100 | System metrics |
| Prometheus | NVIDIA Exporter | HTTP | 9400 | GPU metrics |
| Prometheus | cAdvisor | HTTP | 8080 | Container metrics |
| Prometheus | Grafana | HTTP | 3000 | Grafana metrics |
| Prometheus | AlertManager | HTTP | 9093 | Alert routing |
| Grafana | Prometheus | HTTP | 9090 | Query metrics |
| Grafana | Loki | HTTP | 3100 | Query logs |
| Promtail | Host Logs | File | - | Log collection |
| Promtail | Loki | HTTP | 3100 | Log shipping |
| All Pods | CoreDNS | DNS | 53 | Service discovery |

## Phase 1: Foundation Setup

### Objectives
- Install K3s with NVIDIA support
- Verify GPU access from containers
- Setup persistent storage

### Tasks

#### 1.1 System Prerequisites
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git htop iotop

# Verify NVIDIA driver
nvidia-smi

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

#### 1.2 Install K3s
```bash
# Install K3s with specific configuration
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb --write-kubeconfig-mode 644" sh -

# Wait for K3s to be ready
sudo k3s kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Setup kubectl access
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config
```

#### 1.3 Install NVIDIA Device Plugin
```bash
# Create RuntimeClass for NVIDIA
cat <<EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF

# Deploy NVIDIA device plugin
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.13.0/nvidia-device-plugin.yml

# Verify GPU is available
kubectl get nodes -o json | jq '.items[].status.allocatable."nvidia.com/gpu"'
```

#### 1.4 Setup Storage Classes
```bash
# Create directories for persistent volumes
sudo mkdir -p /var/lib/odin/{prometheus,grafana,loki,alertmanager}
sudo chown -R $USER:$USER /var/lib/odin

# Create local storage class
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
```

### Phase 1 Validation
```bash
# Test GPU access
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  runtimeClassName: nvidia
  containers:
  - name: cuda-test
    image: nvidia/cuda:11.8.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  restartPolicy: Never
EOF

# Check output
kubectl logs gpu-test

# Cleanup
kubectl delete pod gpu-test
```

## Phase 2: Core Monitoring Stack

### Objectives
- Deploy Prometheus with persistent storage
- Deploy Grafana with provisioned dashboards
- Verify basic metrics collection

### Tasks

#### 2.1 Create Monitoring Namespace
```bash
kubectl create namespace monitoring
```

#### 2.2 Deploy Prometheus
```yaml
# prometheus-config.yaml
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
    
    scrape_configs:
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']
    
    - job_name: 'kubernetes-service-discovery'
      kubernetes_sd_configs:
      - role: service
        namespaces:
          names: ['monitoring']
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: $1:${1}
---
# prometheus-deployment.yaml
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
        image: prom/prometheus:v2.40.0
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus/'
          - '--web.enable-lifecycle'
          - '--storage.tsdb.retention.time=30d'
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: storage
          mountPath: /prometheus
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: storage
        persistentVolumeClaim:
          claimName: prometheus-pvc
---
# prometheus-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
spec:
  selector:
    app: prometheus
  ports:
  - name: web
    port: 9090
    targetPort: 9090
  type: ClusterIP
---
# prometheus-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
---
# prometheus-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: local-storage
```

#### 2.3 Deploy Grafana
```yaml
# grafana-deployment.yaml
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
        image: grafana/grafana:9.3.0
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        - name: GF_INSTALL_PLUGINS
          value: "grafana-clock-panel,grafana-piechart-panel"
        volumeMounts:
        - name: storage
          mountPath: /var/lib/grafana
        - name: datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: dashboards-provider
          mountPath: /etc/grafana/provisioning/dashboards
        - name: dashboards
          mountPath: /var/lib/grafana/dashboards
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: grafana-pvc
      - name: datasources
        configMap:
          name: grafana-datasources
      - name: dashboards-provider
        configMap:
          name: grafana-dashboard-provider
      - name: dashboards
        configMap:
          name: grafana-dashboards
---
# grafana-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
  - name: web
    port: 3000
    targetPort: 3000
  type: NodePort
---
# grafana-datasources.yaml
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
      orgId: 1
      url: http://prometheus:9090
      isDefault: true
      editable: true
---
# grafana-dashboard-provider.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provider
  namespace: monitoring
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      updateIntervalSeconds: 10
      allowUiUpdates: true
      options:
        path: /var/lib/grafana/dashboards
---
# grafana-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-storage
```

### Phase 2 Validation
```bash
# Apply all configurations
kubectl apply -f prometheus-config.yaml
kubectl apply -f prometheus-deployment.yaml
kubectl apply -f grafana-deployment.yaml

# Wait for pods to be ready
kubectl wait --for=condition=Ready pods -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=Ready pods -l app=grafana -n monitoring --timeout=300s

# Get Grafana NodePort
export GRAFANA_PORT=$(kubectl get svc grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')
echo "Grafana available at: http://localhost:$GRAFANA_PORT (admin/admin)"

# Verify Prometheus is scraping
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets'
```

## Phase 3: System Metrics Collection

### Objectives
- Deploy Node Exporter for system metrics
- Deploy cAdvisor for container metrics
- Create system dashboard in Grafana

### Tasks

#### 3.1 Deploy Node Exporter
```yaml
# node-exporter-daemonset.yaml
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
        image: prom/node-exporter:v1.5.0
        args:
          - '--path.rootfs=/host'
          - '--path.procfs=/host/proc'
          - '--path.sysfs=/host/sys'
          - '--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/pods/.+)($|/)'
        ports:
        - containerPort: 9100
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
# node-exporter-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9100"
spec:
  selector:
    app: node-exporter
  ports:
  - name: metrics
    port: 9100
    targetPort: 9100
  type: ClusterIP
```

#### 3.2 Deploy cAdvisor
```yaml
# cadvisor-daemonset.yaml
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
      hostNetwork: true
      containers:
      - name: cadvisor
        image: gcr.io/cadvisor/cadvisor:v0.46.0
        ports:
        - containerPort: 8080
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
---
# cadvisor-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: cadvisor
  namespace: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
spec:
  selector:
    app: cadvisor
  ports:
  - name: metrics
    port: 8080
    targetPort: 8080
  type: ClusterIP
```

#### 3.3 Update Prometheus Configuration
```bash
# Update prometheus config to include new targets
cat <<EOF | kubectl apply -f -
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
    
    scrape_configs:
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']
    
    - job_name: 'node-exporter'
      static_configs:
      - targets: ['node-exporter:9100']
    
    - job_name: 'cadvisor'
      static_configs:
      - targets: ['cadvisor:8080']
    
    - job_name: 'kubernetes-service-discovery'
      kubernetes_sd_configs:
      - role: service
        namespaces:
          names: ['monitoring']
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
EOF

# Reload Prometheus
kubectl rollout restart deployment/prometheus -n monitoring
```

#### 3.4 Create System Dashboard
```yaml
# system-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
data:
  system-overview.json: |
    {
      "dashboard": {
        "title": "System Overview",
        "panels": [
          {
            "datasource": "Prometheus",
            "fieldConfig": {
              "defaults": {
                "unit": "percent"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "id": 1,
            "targets": [
              {
                "expr": "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
                "refId": "A"
              }
            ],
            "title": "CPU Usage",
            "type": "gauge"
          },
          {
            "datasource": "Prometheus",
            "fieldConfig": {
              "defaults": {
                "unit": "percent"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
            "id": 2,
            "targets": [
              {
                "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
                "refId": "A"
              }
            ],
            "title": "Memory Usage",
            "type": "gauge"
          },
          {
            "datasource": "Prometheus",
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
            "id": 3,
            "targets": [
              {
                "expr": "rate(node_disk_io_time_seconds_total[5m]) * 100",
                "legendFormat": "{{device}}",
                "refId": "A"
              }
            ],
            "title": "Disk I/O Usage",
            "type": "timeseries"
          }
        ],
        "schemaVersion": 35,
        "style": "dark",
        "tags": ["system"],
        "templating": {
          "list": []
        },
        "time": {
          "from": "now-6h",
          "to": "now"
        },
        "timepicker": {},
        "timezone": "",
        "uid": "system-overview",
        "version": 1
      }
    }
```

### Phase 3 Validation
```bash
# Apply exporters
kubectl apply -f node-exporter-daemonset.yaml
kubectl apply -f cadvisor-daemonset.yaml
kubectl apply -f system-dashboard-configmap.yaml

# Restart Grafana to load dashboard
kubectl rollout restart deployment/grafana -n monitoring

# Verify metrics are being collected
curl http://localhost:9090/api/v1/query?query=node_cpu_seconds_total | jq '.status'
curl http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total | jq '.status'
```

## Phase 4: GPU Metrics Collection

### Objectives
- Deploy NVIDIA DCGM Exporter
- Configure GPU metrics collection
- Create GPU dashboard in Grafana

### Tasks

#### 4.1 Deploy NVIDIA DCGM Exporter
```yaml
# nvidia-exporter-daemonset.yaml
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
      runtimeClassName: nvidia
      containers:
      - name: nvidia-dcgm-exporter
        image: nvcr.io/nvidia/k8s/dcgm-exporter:3.1.3-3.1.4-ubuntu20.04
        env:
        - name: DCGM_EXPORTER_LISTEN
          value: ":9400"
        - name: DCGM_EXPORTER_KUBERNETES
          value: "true"
        ports:
        - containerPort: 9400
        securityContext:
          privileged: true
        volumeMounts:
        - name: pod-gpu-resources
          mountPath: /var/lib/kubelet/pod-resources
          readOnly: true
        resources:
          limits:
            nvidia.com/gpu: 1
      volumes:
      - name: pod-gpu-resources
        hostPath:
          path: /var/lib/kubelet/pod-resources
---
# nvidia-exporter-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nvidia-dcgm-exporter
  namespace: monitoring
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9400"
spec:
  selector:
    app: nvidia-dcgm-exporter
  ports:
  - name: metrics
    port: 9400
    targetPort: 9400
  type: ClusterIP
```

#### 4.2 Update Prometheus for GPU Metrics
```bash
# Add GPU target to Prometheus
kubectl edit configmap prometheus-config -n monitoring
# Add under scrape_configs:
#    - job_name: 'nvidia-gpu'
#      static_configs:
#      - targets: ['nvidia-dcgm-exporter:9400']

kubectl rollout restart deployment/prometheus -n monitoring
```

#### 4.3 Create GPU Dashboard
```yaml
# gpu-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-gpu-dashboard
  namespace: monitoring
data:
  gpu-metrics.json: |
    {
      "dashboard": {
        "title": "NVIDIA GPU Metrics",
        "panels": [
          {
            "datasource": "Prometheus",
            "fieldConfig": {
              "defaults": {
                "unit": "celsius"
              }
            },
            "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
            "id": 1,
            "targets": [
              {
                "expr": "DCGM_FI_DEV_GPU_TEMP",
                "refId": "A"
              }
            ],
            "title": "GPU Temperature",
            "type": "gauge"
          },
          {
            "datasource": "Prometheus",
            "fieldConfig": {
              "defaults": {
                "unit": "percent"
              }
            },
            "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0},
            "id": 2,
            "targets": [
              {
                "expr": "DCGM_FI_DEV_GPU_UTIL",
                "refId": "A"
              }
            ],
            "title": "GPU Utilization",
            "type": "gauge"
          },
          {
            "datasource": "Prometheus",
            "fieldConfig": {
              "defaults": {
                "unit": "watt"
              }
            },
            "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0},
            "id": 3,
            "targets": [
              {
                "expr": "DCGM_FI_DEV_POWER_USAGE",
                "refId": "A"
              }
            ],
            "title": "Power Usage",
            "type": "gauge"
          },
          {
            "datasource": "Prometheus",
            "fieldConfig": {
              "defaults": {
                "unit": "bytes"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
            "id": 4,
            "targets": [
              {
                "expr": "DCGM_FI_DEV_FB_USED",
                "legendFormat": "Used",
                "refId": "A"
              },
              {
                "expr": "DCGM_FI_DEV_FB_FREE",
                "legendFormat": "Free",
                "refId": "B"
              }
            ],
            "title": "GPU Memory",
            "type": "timeseries"
          },
          {
            "datasource": "Prometheus",
            "fieldConfig": {
              "defaults": {
                "unit": "hertz"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
            "id": 5,
            "targets": [
              {
                "expr": "DCGM_FI_DEV_SM_CLOCK * 1000000",
                "legendFormat": "SM Clock",
                "refId": "A"
              },
              {
                "expr": "DCGM_FI_DEV_MEM_CLOCK * 1000000",
                "legendFormat": "Memory Clock",
                "refId": "B"
              }
            ],
            "title": "GPU Clocks",
            "type": "timeseries"
          }
        ],
        "schemaVersion": 35,
        "style": "dark",
        "tags": ["gpu"],
        "uid": "gpu-metrics",
        "version": 1
      }
    }
```

### Phase 4 Validation
```bash
# Apply GPU exporter
kubectl apply -f nvidia-exporter-daemonset.yaml
kubectl apply -f gpu-dashboard-configmap.yaml

# Verify GPU metrics
curl http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_TEMP | jq '.data.result'

# Test GPU workload to see metrics change
kubectl run gpu-stress --rm -it --restart=Never --image=nvidia/cuda:11.8.0-base-ubuntu22.04 --limits=nvidia.com/gpu=1 -- nvidia-smi dmon -s pucvmet
```

## Phase 5: Log Collection and Monitoring

### Objectives
- Deploy Loki for log aggregation
- Deploy Promtail for log collection
- Create logs dashboard in Grafana

### Tasks

#### 5.1 Deploy Loki
```yaml
# loki-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki
  namespace: monitoring
spec:
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
          - -config.file=/etc/loki/local-config.yaml
        ports:
        - containerPort: 3100
        volumeMounts:
        - name: storage
          mountPath: /loki
        - name: config
          mountPath: /etc/loki
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: loki-pvc
      - name: config
        configMap:
          name: loki-config
---
# loki-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: monitoring
data:
  local-config.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
    ingester:
      lifecycler:
        address: 127.0.0.1
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
      chunk_idle_period: 5m
      chunk_retain_period: 30s
    schema_config:
      configs:
        - from: 2023-01-01
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/boltdb-shipper-active
        cache_location: /loki/boltdb-shipper-cache
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
---
# loki-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: monitoring
spec:
  selector:
    app: loki
  ports:
  - name: http
    port: 3100
    targetPort: 3100
  type: ClusterIP
---
# loki-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: loki-pvc
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: local-storage
```

#### 5.2 Deploy Promtail
```yaml
# promtail-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      serviceAccountName: promtail
      containers:
      - name: promtail
        image: grafana/promtail:2.9.0
        args:
          - -config.file=/etc/promtail/config.yml
        env:
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: pods
          mountPath: /var/log/pods
          readOnly: true
        - name: docker
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: varlog
        hostPath:
          path: /var/log
      - name: pods
        hostPath:
          path: /var/log/pods
      - name: docker
        hostPath:
          path: /var/lib/docker/containers
---
# promtail-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: monitoring
data:
  config.yml: |
    server:
      http_listen_port: 9080
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
          __path__: /var/log/*.log
    - job_name: containers
      static_configs:
      - targets:
          - localhost
        labels:
          job: containerlogs
          __path__: /var/lib/docker/containers/*/*log
      pipeline_stages:
      - json:
          expressions:
            output: log
            stream: stream
            attrs:
      - json:
          expressions:
            tag:
          source: attrs
      - regex:
          expression: (?P<container_name>(?:[^|]*))\|(?P<image_name>(?:[^|]*))
          source: tag
      - timestamp:
          format: RFC3339Nano
          source: time
      - labels:
          stream:
          container_name:
          image_name:
      - output:
          source: output
---
# promtail-rbac.yaml
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
  - services
  - pods
  verbs: ["get", "list", "watch"]
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
```

#### 5.3 Add Loki to Grafana
```bash
# Update Grafana datasources to include Loki
cat <<EOF | kubectl apply -f -
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
      orgId: 1
      url: http://prometheus:9090
      isDefault: true
      editable: true
  loki.yaml: |
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      access: proxy
      orgId: 1
      url: http://loki:3100
      isDefault: false
      editable: true
EOF

kubectl rollout restart deployment/grafana -n monitoring
```

#### 5.4 Create Logs Dashboard
```yaml
# logs-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-logs-dashboard
  namespace: monitoring
data:
  logs-overview.json: |
    {
      "dashboard": {
        "title": "Logs Overview",
        "panels": [
          {
            "datasource": "Loki",
            "fieldConfig": {
              "defaults": {}
            },
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0},
            "id": 1,
            "options": {
              "showTime": true,
              "showLabels": true,
              "showCommonLabels": false,
              "wrapLogMessage": true,
              "sortOrder": "Descending",
              "dedupStrategy": "none"
            },
            "targets": [
              {
                "expr": "{job=\"varlogs\"}",
                "refId": "A"
              }
            ],
            "title": "System Logs",
            "type": "logs"
          },
          {
            "datasource": "Loki",
            "fieldConfig": {
              "defaults": {}
            },
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
            "id": 2,
            "options": {
              "showTime": true,
              "showLabels": true,
              "showCommonLabels": false,
              "wrapLogMessage": true,
              "sortOrder": "Descending",
              "dedupStrategy": "none"
            },
            "targets": [
              {
                "expr": "{job=\"containerlogs\"}",
                "refId": "A"
              }
            ],
            "title": "Container Logs",
            "type": "logs"
          },
          {
            "datasource": "Loki",
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16},
            "id": 3,
            "targets": [
              {
                "expr": "rate({job=~\".+\"}[5m])",
                "refId": "A"
              }
            ],
            "title": "Log Rate",
            "type": "timeseries"
          }
        ],
        "schemaVersion": 35,
        "style": "dark",
        "tags": ["logs"],
        "uid": "logs-overview",
        "version": 1
      }
    }
```

### Phase 5 Validation
```bash
# Apply log collection stack
kubectl apply -f loki-deployment.yaml
kubectl apply -f promtail-daemonset.yaml
kubectl apply -f logs-dashboard-configmap.yaml

# Wait for pods
kubectl wait --for=condition=Ready pods -l app=loki -n monitoring --timeout=300s
kubectl wait --for=condition=Ready pods -l app=promtail -n monitoring --timeout=300s

# Test log ingestion
echo "Test log entry" | sudo tee -a /var/log/test.log
sleep 30

# Query Loki for the test log
curl -G -s "http://localhost:3100/loki/api/v1/query" --data-urlencode 'query={job="varlogs"} |= "Test log entry"' | jq '.data.result'
```

## Final Validation & Success Criteria

### 1. System Metrics Dashboard
```bash
# Verify node metrics
curl http://localhost:9090/api/v1/query?query=node_cpu_seconds_total
curl http://localhost:9090/api/v1/query?query=node_memory_MemTotal_bytes
curl http://localhost:9090/api/v1/query?query=node_filesystem_size_bytes
curl http://localhost:9090/api/v1/query?query=node_disk_io_time_seconds_total
```

### 2. GPU Metrics Dashboard
```bash
# Verify GPU metrics
curl http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_TEMP
curl http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL
curl http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_POWER_USAGE
curl http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_FB_USED
```

### 3. Logs Dashboard
```bash
# Verify log collection
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job=~".+"}' \
  --data-urlencode 'start=1h' | jq '.data.result | length'
```

## Maintenance Scripts

### backup-odin.sh
```bash
#!/bin/bash
# Backup ODIN persistent data
BACKUP_DIR="/var/backups/odin/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup Prometheus data
kubectl exec -n monitoring deployment/prometheus -- tar czf - /prometheus | tar xzf - -C "$BACKUP_DIR"

# Backup Grafana data
kubectl exec -n monitoring deployment/grafana -- tar czf - /var/lib/grafana | tar xzf - -C "$BACKUP_DIR"

# Backup Loki data
kubectl exec -n monitoring deployment/loki -- tar czf - /loki | tar xzf - -C "$BACKUP_DIR"

echo "Backup completed to: $BACKUP_DIR"
```

### health-check.sh
```bash
#!/bin/bash
# Check ODIN health
echo "=== ODIN Health Check ==="

# Check pods
echo "Checking pods..."
kubectl get pods -n monitoring

# Check services
echo "Checking services..."
kubectl get svc -n monitoring

# Check metrics
echo "Checking Prometheus targets..."
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .job, health: .health}'

# Check Grafana
echo "Checking Grafana..."
curl -s http://localhost:$GRAFANA_PORT/api/health | jq .

# Check Loki
echo "Checking Loki..."
curl -s http://localhost:3100/ready
```

## Troubleshooting Guide

### Common Issues

1. **GPU metrics not appearing**
   - Verify NVIDIA runtime: `kubectl get runtimeclass`
   - Check device plugin: `kubectl get pods -n kube-system | grep nvidia`
   - Test GPU access: `kubectl run gpu-test --rm -it --image=nvidia/cuda:11.8.0-base-ubuntu22.04 --limits=nvidia.com/gpu=1 -- nvidia-smi`

2. **Prometheus targets down**
   - Check service endpoints: `kubectl get endpoints -n monitoring`
   - Verify network policies: `kubectl get networkpolicies -n monitoring`
   - Check pod logs: `kubectl logs -n monitoring deployment/prometheus`

3. **No logs in Loki**
   - Check Promtail permissions: `kubectl logs -n monitoring daemonset/promtail`
   - Verify log paths exist: `kubectl exec -n monitoring daemonset/promtail -- ls -la /var/log`
   - Test Loki ingestion: `curl -X POST http://localhost:3100/loki/api/v1/push -H "Content-Type: application/json" -d '{"streams": [{"stream": {"job": "test"}, "values": [["'$(date +%s)000000000'", "test log"]]}]}'`

## Success Indicators

✅ All pods in monitoring namespace are Running
✅ Grafana accessible via NodePort
✅ System dashboard shows CPU, Memory, Disk, I/O metrics
✅ GPU dashboard shows temperature, utilization, power, memory
✅ Logs dashboard shows system and container logs
✅ All Prometheus targets are UP
✅ Persistent data is retained across pod restarts

## Post-Deployment Steps

1. **Configure Grafana**
   - Change admin password
   - Setup SMTP for alerts
   - Configure data retention

2. **Setup Monitoring Alerts**
   - High CPU/Memory usage
   - GPU temperature threshold
   - Disk space warnings
   - Service down alerts

3. **Backup Strategy**
   - Schedule daily backups
   - Test restore procedures
   - Monitor backup sizes

4. **Security Hardening**
   - Enable RBAC restrictions
   - Setup network policies
   - Configure TLS for services
   - Implement authentication

This completes the ODIN Kubernetes deployment on Ubuntu 22.04 with full NVIDIA RTX support.