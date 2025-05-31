# Greenfield ODIN Deployment on Razer Blade 18 with Ubuntu 22.04 and NVIDIA GPU

This guide provides step-by-step instructions for deploying the ODIN (Observability Dashboard for Infrastructure and NVIDIA) monitoring stack on a fresh Razer Blade 18 laptop running Ubuntu 22.04 with NVIDIA GPU support.

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Pre-Installation Checklist](#pre-installation-checklist)
3. [Base System Setup](#base-system-setup)
4. [NVIDIA GPU Setup](#nvidia-gpu-setup)
5. [Kubernetes (K3s) Installation](#kubernetes-k3s-installation)
6. [ODIN Core Components](#odin-core-components)
7. [Custom Exporters Deployment](#custom-exporters-deployment)
8. [Dashboard Configuration](#dashboard-configuration)
9. [Alerting Setup](#alerting-setup)
10. [Verification & Testing](#verification--testing)
11. [Backup & Maintenance](#backup--maintenance)
12. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Hardware Requirements

**Minimum:**
- **CPU**: Intel Core i7 or AMD Ryzen 7 (8+ cores recommended)
- **RAM**: 16GB (32GB recommended)
- **Storage**: 100GB free space (NVMe SSD recommended)
- **GPU**: NVIDIA RTX 3000 series or newer
- **Network**: Stable internet connection for initial setup

**Tested Configuration (Razer Blade 18):**
- CPU: Intel Core i9-13950HX
- RAM: 32GB DDR5
- Storage: 1TB NVMe SSD
- GPU: NVIDIA RTX 4080 Laptop GPU
- Display: 18" QHD+ 240Hz

### Software Requirements

**Operating System:**
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Kernel: 5.15 or newer

**NVIDIA/CUDA Requirements:**
- NVIDIA Driver: 525.x or newer
- CUDA Toolkit: 11.8 or newer (optional)
- NVIDIA Container Toolkit: Latest version

**Other Dependencies:**
- Docker: 20.10+ (installed by K3s)
- kubectl: 1.25+
- git: 2.25+
- curl, wget, jq, htop

---

## Pre-Installation Checklist

Before starting the deployment, ensure:

- [ ] Fresh Ubuntu 22.04 installation completed
- [ ] System fully updated (`sudo apt update && sudo apt upgrade`)
- [ ] Swap disabled or limited (for Kubernetes)
- [ ] Static IP or reliable DHCP
- [ ] SSH access configured (optional but recommended)
- [ ] At least 100GB free disk space
- [ ] NVIDIA GPU detected (`lspci | grep -i nvidia`)

---

## Base System Setup

### 1. Update System and Install Dependencies

```bash
# Update package lists
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    jq \
    net-tools \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential \
    python3-pip \
    python3-venv

# Install monitoring tools
sudo apt install -y \
    sysstat \
    iotop \
    nmon \
    dstat
```

### 2. Configure System Settings

```bash
# Disable swap (required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Configure kernel parameters
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF

sudo sysctl --system

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### 3. Configure Firewall

```bash
# Allow required ports
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 6443/tcp  # Kubernetes API
sudo ufw allow 10250/tcp # Kubelet
sudo ufw allow 30000:32767/tcp # NodePort Services

# Enable firewall
sudo ufw --force enable
```

---

## NVIDIA GPU Setup

### 1. Install NVIDIA Drivers

```bash
# Add NVIDIA PPA
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update

# Install recommended driver
sudo apt install -y nvidia-driver-535

# Reboot to load driver
sudo reboot
```

### 2. Verify NVIDIA Installation

```bash
# After reboot, verify driver
nvidia-smi

# Expected output shows GPU details
# +-----------------------------------------------------------------------------+
# | NVIDIA-SMI 535.x.xx    Driver Version: 535.x.xx    CUDA Version: 12.2     |
# |-------------------------------+----------------------+----------------------+
```

### 3. Install NVIDIA Container Toolkit

```bash
# Add NVIDIA Container Toolkit repository
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    sudo tee /etc/apt/sources.list.d/nvidia-docker.list

# Install nvidia-container-toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure Docker runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 4. Install CUDA Toolkit (Optional)

```bash
# Install CUDA toolkit for development
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
sudo dpkg -i cuda-keyring_1.0-1_all.deb
sudo apt update
sudo apt install -y cuda-toolkit-11-8

# Add CUDA to PATH
echo 'export PATH=/usr/local/cuda-11.8/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```

---

## Kubernetes (K3s) Installation

### 1. Install K3s

```bash
# Install K3s without traefik (we'll use NodePort)
curl -sfL https://get.k3s.io | sh -s - \
    --disable traefik \
    --write-kubeconfig-mode 644

# Wait for K3s to be ready
sudo systemctl status k3s

# Configure kubectl access
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# Verify cluster
kubectl get nodes
```

### 2. Install NVIDIA Device Plugin

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
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# Verify GPU is available
kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu" != null)'
```

### 3. Create Monitoring Namespace

```bash
# Create namespace
kubectl create namespace monitoring

# Set as default namespace (optional)
kubectl config set-context --current --namespace=monitoring
```

---

## ODIN Core Components

### 1. Create Storage Class and PVs

```bash
# Create storage directory
sudo mkdir -p /var/lib/odin/{prometheus,grafana,loki,alertmanager}
sudo chown -R $USER:$USER /var/lib/odin

# Create storage class
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

# Create Persistent Volumes
for component in prometheus grafana loki alertmanager; do
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${component}-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /var/lib/odin/${component}
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: Exists
EOF
done
```

### 2. Deploy Prometheus

```bash
cat <<'EOF' | kubectl apply -f -
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

    alerting:
      alertmanagers:
        - static_configs:
            - targets: ['alertmanager:9093']

    rule_files:
      - "/etc/prometheus/rules/*.yaml"

    scrape_configs:
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']

    - job_name: 'node-exporter'
      static_configs:
      - targets: ['node-exporter:9100']

    - job_name: 'kube-state-metrics'
      static_configs:
      - targets: ['kube-state-metrics:8080']

    - job_name: 'cadvisor'
      static_configs:
      - targets: ['cadvisor:8080']

    - job_name: 'power-exporter'
      static_configs:
      - targets: ['power-exporter:9402']

    - job_name: 'process-exporter'
      static_configs:
      - targets: ['process-exporter:9256']

    - job_name: 'claude-code-exporter'
      static_configs:
      - targets: ['claude-code-exporter:9403']
---
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
      storage: 10Gi
  storageClassName: local-storage
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
      containers:
      - name: prometheus
        image: prom/prometheus:v2.45.0
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus'
          - '--web.enable-lifecycle'
          - '--storage.tsdb.retention.time=30d'
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: storage
          mountPath: /prometheus
        - name: rules
          mountPath: /etc/prometheus/rules
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1"
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: storage
        persistentVolumeClaim:
          claimName: prometheus-pvc
      - name: rules
        configMap:
          name: prometheus-rules
          optional: true
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
  - name: web
    port: 9090
    targetPort: 9090
    nodePort: 31493
  type: NodePort
EOF
```

### 3. Deploy Grafana

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-config
  namespace: monitoring
data:
  grafana.ini: |
    [server]
    root_url = %(protocol)s://%(domain)s:%(http_port)s/
    
    [security]
    admin_user = admin
    admin_password = admin
    
    [dashboards]
    default_home_dashboard_path = /var/lib/grafana/dashboards/system-overview.json
    
    [auth.anonymous]
    enabled = true
    org_role = Viewer
---
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
      url: http://prometheus.monitoring.svc.cluster.local:9090
      isDefault: true
  loki.yaml: |
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring.svc.cluster.local:3100
---
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
        env:
        - name: GF_INSTALL_PLUGINS
          value: "grafana-clock-panel,grafana-simple-json-datasource"
        volumeMounts:
        - name: config
          mountPath: /etc/grafana
        - name: datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: dashboard-provider
          mountPath: /etc/grafana/provisioning/dashboards
        - name: storage
          mountPath: /var/lib/grafana
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: grafana-config
      - name: datasources
        configMap:
          name: grafana-datasources
      - name: dashboard-provider
        configMap:
          name: grafana-dashboard-provider
      - name: storage
        persistentVolumeClaim:
          claimName: grafana-pvc
---
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
    nodePort: 31494
  type: NodePort
EOF
```

### 4. Deploy Loki and Promtail

```bash
# Deploy Loki
cat <<'EOF' | kubectl apply -f -
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

    common:
      path_prefix: /tmp/loki
      storage:
        filesystem:
          chunks_directory: /tmp/loki/chunks
          rules_directory: /tmp/loki/rules
      replication_factor: 1
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory

    schema_config:
      configs:
        - from: 2020-10-24
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h

    storage_config:
      boltdb_shipper:
        active_index_directory: /tmp/loki/index
        shared_store: filesystem
        cache_location: /tmp/loki/index_cache
      filesystem:
        directory: /tmp/loki/chunks

    limits_config:
      enforce_metric_name: false
      retention_period: 168h
      max_query_length: 720h
      split_queries_by_interval: 15m

    compactor:
      working_directory: /tmp/loki/compactor
      shared_store: filesystem
      compaction_interval: 10m
      retention_enabled: true
      retention_delete_delay: 2h
---
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
      storage: 10Gi
  storageClassName: local-storage
---
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
        ports:
        - containerPort: 3100
        volumeMounts:
        - name: config
          mountPath: /etc/loki
        - name: storage
          mountPath: /tmp/loki
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: loki-config
      - name: storage
        persistentVolumeClaim:
          claimName: loki-pvc
---
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
EOF

# Deploy Promtail
cat <<'EOF' | kubectl apply -f -
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
      - url: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push

    scrape_configs:
    - job_name: pods
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - monitoring
      relabel_configs:
      - source_labels: ['__meta_kubernetes_pod_node_name']
        target_label: 'node'
      - source_labels: ['__meta_kubernetes_namespace']
        target_label: 'namespace'
      - source_labels: ['__meta_kubernetes_pod_name']
        target_label: 'pod'
      - source_labels: ['__meta_kubernetes_container_name']
        target_label: 'container'
      pipeline_stages:
      - docker: {}

    - job_name: system
      static_configs:
      - targets:
          - localhost
        labels:
          job: system
          __path__: /var/log/*.log
---
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
        - -config.file=/etc/promtail/promtail.yaml
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: positions
          mountPath: /tmp
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: varlog
        hostPath:
          path: /var/log
      - name: positions
        emptyDir: {}
---
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
  resources: ["nodes", "pods", "services"]
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
EOF
```

### 5. Deploy AlertManager

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      smtp_smarthost: 'localhost:587'
      smtp_from: 'odin-alerts@localhost'
      resolve_timeout: 5m
    
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match:
          severity: critical
        receiver: 'critical-alerts'
      - match:
          severity: warning
        receiver: 'warning-alerts'
      - match:
          alertname: GPUHighTemperature
        receiver: 'gpu-alerts'
    
    receivers:
    - name: 'default'
      webhook_configs:
      - url: 'http://webhook-logger.monitoring.svc.cluster.local:8080/webhook'
        send_resolved: true
    
    - name: 'critical-alerts'
      webhook_configs:
      - url: 'http://webhook-logger.monitoring.svc.cluster.local:8080/webhook/critical'
        send_resolved: true
    
    - name: 'warning-alerts'
      webhook_configs:
      - url: 'http://webhook-logger.monitoring.svc.cluster.local:8080/webhook/warning'
        send_resolved: true
    
    - name: 'gpu-alerts'
      webhook_configs:
      - url: 'http://webhook-logger.monitoring.svc.cluster.local:8080/webhook/gpu'
        send_resolved: true
---
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
  storageClassName: local-storage
---
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
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
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
  - name: web
    port: 9093
    targetPort: 9093
    nodePort: 31495
  type: NodePort
EOF
```

---

## Custom Exporters Deployment

### 1. Deploy Node Exporter

```bash
cat <<'EOF' | kubectl apply -f -
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
      hostNetwork: true
      hostPID: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.6.0
        args:
          - '--path.procfs=/host/proc'
          - '--path.sysfs=/host/sys'
          - '--path.rootfs=/host/root'
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
          mountPath: /host/root
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
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
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    app: node-exporter
  ports:
  - name: metrics
    port: 9100
    targetPort: 9100
  type: ClusterIP
EOF
```

### 2. Deploy Power Exporter (GPU Monitoring)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: power-exporter-script
  namespace: monitoring
data:
  power_exporter.py: |
    #!/usr/bin/env python3
    import subprocess
    import json
    import time
    import re
    import os
    from http.server import HTTPServer, BaseHTTPRequestHandler
    from prometheus_client import CollectorRegistry, Gauge, generate_latest
    from datetime import datetime

    # Create metrics
    registry = CollectorRegistry()

    # GPU Metrics
    gpu_temp = Gauge('nvidia_gpu_temperature_celsius', 'GPU Temperature in Celsius', ['gpu', 'uuid'], registry=registry)
    gpu_power = Gauge('nvidia_gpu_power_draw_watts', 'GPU Power Draw in Watts', ['gpu', 'uuid'], registry=registry)
    gpu_memory_used = Gauge('nvidia_gpu_memory_used_mb', 'GPU Memory Used in MB', ['gpu', 'uuid'], registry=registry)
    gpu_memory_total = Gauge('nvidia_gpu_memory_total_mb', 'GPU Memory Total in MB', ['gpu', 'uuid'], registry=registry)
    gpu_utilization = Gauge('nvidia_gpu_utilization_percent', 'GPU Utilization Percentage', ['gpu', 'uuid'], registry=registry)
    gpu_fan_speed = Gauge('nvidia_gpu_fan_speed_percent', 'GPU Fan Speed Percentage', ['gpu', 'uuid'], registry=registry)

    # CPU Power Metrics
    cpu_package_power = Gauge('node_cpu_package_power_watts', 'CPU Package Power in Watts', ['package'], registry=registry)
    cpu_core_power = Gauge('node_cpu_core_power_watts', 'CPU Core Power in Watts', ['package'], registry=registry)
    cpu_uncore_power = Gauge('node_cpu_uncore_power_watts', 'CPU Uncore Power in Watts', ['package'], registry=registry)
    
    # Battery Metrics
    battery_percentage = Gauge('node_power_supply_capacity', 'Battery Capacity Percentage', ['power_supply'], registry=registry)
    battery_power = Gauge('node_battery_power_watts', 'Battery Power in Watts', ['power_supply'], registry=registry)
    battery_health = Gauge('node_battery_health_percent', 'Battery Health Percentage', ['power_supply'], registry=registry)

    # Health tracking
    component_health = {
        'rapl': {'healthy': True, 'last_success': None, 'error': None},
        'battery': {'healthy': True, 'last_success': None, 'error': None},
        'gpu': {'healthy': True, 'last_success': None, 'error': None}
    }

    def get_gpu_metrics():
        try:
            cmd = ['nvidia-smi', '--query-gpu=index,uuid,temperature.gpu,power.draw,memory.used,memory.total,utilization.gpu,fan.speed', '--format=csv,noheader,nounits']
            output = subprocess.check_output(cmd).decode('utf-8')
            
            for line in output.strip().split('\n'):
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 8:
                    idx, uuid, temp, power, mem_used, mem_total, util, fan = parts
                    
                    gpu_temp.labels(gpu=f'gpu{idx}', uuid=uuid).set(float(temp))
                    gpu_power.labels(gpu=f'gpu{idx}', uuid=uuid).set(float(power))
                    gpu_memory_used.labels(gpu=f'gpu{idx}', uuid=uuid).set(float(mem_used))
                    gpu_memory_total.labels(gpu=f'gpu{idx}', uuid=uuid).set(float(mem_total))
                    gpu_utilization.labels(gpu=f'gpu{idx}', uuid=uuid).set(float(util))
                    gpu_fan_speed.labels(gpu=f'gpu{idx}', uuid=uuid).set(float(fan))
            
            component_health['gpu']['healthy'] = True
            component_health['gpu']['last_success'] = datetime.now().isoformat()
            component_health['gpu']['error'] = None
            
        except Exception as e:
            component_health['gpu']['healthy'] = False
            component_health['gpu']['error'] = str(e)

    def get_cpu_power_metrics():
        try:
            # Read Intel RAPL
            rapl_path = '/sys/class/powercap/intel-rapl'
            if os.path.exists(rapl_path):
                for i in range(10):
                    pkg_path = f'{rapl_path}/intel-rapl:{i}'
                    if os.path.exists(pkg_path):
                        with open(f'{pkg_path}/energy_uj', 'r') as f:
                            energy = float(f.read().strip()) / 1e6
                            cpu_package_power.labels(package=str(i)).set(energy)
            
            component_health['rapl']['healthy'] = True
            component_health['rapl']['last_success'] = datetime.now().isoformat()
            component_health['rapl']['error'] = None
            
        except Exception as e:
            component_health['rapl']['healthy'] = False
            component_health['rapl']['error'] = str(e)

    def get_battery_metrics():
        try:
            # Read battery info
            battery_path = '/sys/class/power_supply/BAT0'
            if os.path.exists(battery_path):
                with open(f'{battery_path}/capacity', 'r') as f:
                    capacity = int(f.read().strip())
                    battery_percentage.labels(power_supply='BAT0').set(capacity)
                
                # Calculate battery power if available
                if os.path.exists(f'{battery_path}/power_now'):
                    with open(f'{battery_path}/power_now', 'r') as f:
                        power = float(f.read().strip()) / 1e6
                        battery_power.labels(power_supply='BAT0').set(power)
            
            component_health['battery']['healthy'] = True
            component_health['battery']['last_success'] = datetime.now().isoformat()
            component_health['battery']['error'] = None
            
        except Exception as e:
            component_health['battery']['healthy'] = False
            component_health['battery']['error'] = str(e)

    class MetricsHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/metrics':
                get_gpu_metrics()
                get_cpu_power_metrics()
                get_battery_metrics()
                
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; version=0.0.4')
                self.end_headers()
                self.wfile.write(generate_latest(registry))
            
            elif self.path in ['/health', '/healthz', '/ready']:
                overall_health = all(comp['healthy'] for comp in component_health.values())
                status_code = 200 if overall_health else 503
                
                self.send_response(status_code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                
                health_data = {
                    'status': 'healthy' if overall_health else 'unhealthy',
                    'timestamp': datetime.now().isoformat(),
                    'components': component_health
                }
                self.wfile.write(json.dumps(health_data, indent=2).encode())
            
            else:
                self.send_response(404)
                self.end_headers()

    if __name__ == '__main__':
        server = HTTPServer(('0.0.0.0', 9402), MetricsHandler)
        print('Power exporter listening on port 9402')
        server.serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: power-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: power-exporter
  template:
    metadata:
      labels:
        app: power-exporter
    spec:
      hostNetwork: true
      runtimeClassName: nvidia
      containers:
      - name: power-exporter
        image: python:3.11-slim
        command: ["python3", "/app/power_exporter.py"]
        ports:
        - containerPort: 9402
        volumeMounts:
        - name: script
          mountPath: /app
        - name: powercap
          mountPath: /sys/class/powercap
          readOnly: true
        - name: power-supply
          mountPath: /sys/class/power_supply
          readOnly: true
        env:
        - name: NVIDIA_VISIBLE_DEVICES
          value: "all"
        - name: NVIDIA_DRIVER_CAPABILITIES
          value: "utility"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
            nvidia.com/gpu: "1"
        livenessProbe:
          httpGet:
            path: /health
            port: 9402
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 9402
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: script
        configMap:
          name: power-exporter-script
          defaultMode: 0755
      - name: powercap
        hostPath:
          path: /sys/class/powercap
      - name: power-supply
        hostPath:
          path: /sys/class/power_supply
---
apiVersion: v1
kind: Service
metadata:
  name: power-exporter
  namespace: monitoring
spec:
  selector:
    app: power-exporter
  ports:
  - name: metrics
    port: 9402
    targetPort: 9402
  type: ClusterIP
EOF

# Install Python dependencies in the container
kubectl exec -n monitoring deployment/power-exporter -- pip install prometheus-client
```

### 3. Deploy Process Exporter

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: process-exporter-config
  namespace: monitoring
data:
  process-exporter.yml: |
    process_names:
      - name: "{{.Comm}}"
        cmdline:
        - '.+'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: process-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: process-exporter
  template:
    metadata:
      labels:
        app: process-exporter
    spec:
      hostPID: true
      containers:
      - name: process-exporter
        image: ncabatoff/process-exporter:0.7.10
        args:
          - '--config.path=/config/process-exporter.yml'
          - '--web.listen-address=:9256'
          - '--procfs=/host/proc'
        ports:
        - containerPort: 9256
        volumeMounts:
        - name: config
          mountPath: /config
        - name: proc
          mountPath: /host/proc
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: process-exporter-config
      - name: proc
        hostPath:
          path: /proc
---
apiVersion: v1
kind: Service
metadata:
  name: process-exporter
  namespace: monitoring
spec:
  selector:
    app: process-exporter
  ports:
  - name: metrics
    port: 9256
    targetPort: 9256
  type: ClusterIP
EOF
```

### 4. Deploy Claude Code Exporter

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-code-exporter-script
  namespace: monitoring
data:
  claude_code_exporter.py: |
    #!/usr/bin/env python3
    import psutil
    import time
    import os
    import json
    from http.server import HTTPServer, BaseHTTPRequestHandler
    from prometheus_client import CollectorRegistry, Gauge, Counter, generate_latest
    from datetime import datetime

    # Create registry
    registry = CollectorRegistry()

    # Claude process metrics
    claude_process_cpu = Gauge('claude_process_cpu_percent', 'Claude process CPU usage percentage', ['pid', 'cmd'], registry=registry)
    claude_process_memory = Gauge('claude_process_memory_mb', 'Claude process memory usage in MB', ['pid', 'cmd'], registry=registry)
    claude_process_threads = Gauge('claude_process_threads', 'Claude process thread count', ['pid', 'cmd'], registry=registry)
    claude_process_files = Gauge('claude_process_open_files', 'Claude process open file count', ['pid', 'cmd'], registry=registry)
    claude_process_connections = Gauge('claude_process_connections', 'Claude process network connections', ['pid', 'cmd', 'type'], registry=registry)
    claude_process_uptime = Gauge('claude_process_uptime_seconds', 'Claude process uptime in seconds', ['pid', 'cmd'], registry=registry)

    # Token metrics
    claude_tokens_used = Counter('claude_api_tokens_used_total', 'Total Claude API tokens used', ['type'], registry=registry)
    claude_api_cost = Counter('claude_api_cost_dollars', 'Total Claude API cost in dollars', registry=registry)

    def is_claude_process(proc):
        """Detect if a process is Claude-related"""
        try:
            # Check process name
            proc_name = proc.name().lower()
            claude_names = ['claude', 'anthropic', 'code-editor', 'cursor']
            if any(name in proc_name for name in claude_names):
                return True
            
            # Check command line
            cmdline = ' '.join(proc.cmdline()).lower()
            if any(name in cmdline for name in claude_names):
                return True
            
            # Check environment variables
            try:
                env_vars = proc.environ()
                claude_env_vars = ['ANTHROPIC_API_KEY', 'CLAUDE_API_KEY', 'CLAUDE_']
                for var in claude_env_vars:
                    if any(var in env_key for env_key in env_vars.keys()):
                        return True
            except:
                pass
            
            return False
        except:
            return False

    def collect_metrics():
        """Collect metrics for Claude-related processes"""
        claude_processes = []
        
        for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'cpu_percent', 'memory_info', 'num_threads', 'connections', 'create_time']):
            try:
                if is_claude_process(proc):
                    # Get process info
                    pid = proc.pid
                    cmd = proc.name()
                    
                    # CPU usage
                    cpu_percent = proc.cpu_percent(interval=0.1)
                    claude_process_cpu.labels(pid=str(pid), cmd=cmd).set(cpu_percent)
                    
                    # Memory usage
                    memory_mb = proc.memory_info().rss / 1024 / 1024
                    claude_process_memory.labels(pid=str(pid), cmd=cmd).set(memory_mb)
                    
                    # Thread count
                    num_threads = proc.num_threads()
                    claude_process_threads.labels(pid=str(pid), cmd=cmd).set(num_threads)
                    
                    # Open files
                    try:
                        num_files = len(proc.open_files())
                        claude_process_files.labels(pid=str(pid), cmd=cmd).set(num_files)
                    except:
                        pass
                    
                    # Network connections
                    try:
                        connections = proc.connections()
                        conn_types = {}
                        for conn in connections:
                            conn_type = conn.type.name
                            conn_types[conn_type] = conn_types.get(conn_type, 0) + 1
                        
                        for conn_type, count in conn_types.items():
                            claude_process_connections.labels(pid=str(pid), cmd=cmd, type=conn_type).set(count)
                    except:
                        pass
                    
                    # Process uptime
                    uptime = time.time() - proc.create_time()
                    claude_process_uptime.labels(pid=str(pid), cmd=cmd).set(uptime)
                    
                    claude_processes.append({
                        'pid': pid,
                        'cmd': cmd,
                        'cpu': cpu_percent,
                        'memory_mb': memory_mb
                    })
            except:
                continue
        
        return claude_processes

    class MetricsHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/metrics':
                processes = collect_metrics()
                
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; version=0.0.4')
                self.end_headers()
                self.wfile.write(generate_latest(registry))
            
            elif self.path in ['/health', '/healthz']:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                
                health_data = {
                    'status': 'healthy',
                    'timestamp': datetime.now().isoformat(),
                    'service': 'claude-code-exporter'
                }
                self.wfile.write(json.dumps(health_data).encode())
            
            else:
                self.send_response(404)
                self.end_headers()

    if __name__ == '__main__':
        server = HTTPServer(('0.0.0.0', 9403), MetricsHandler)
        print('Claude Code exporter listening on port 9403')
        server.serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-code-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: claude-code-exporter
  template:
    metadata:
      labels:
        app: claude-code-exporter
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: claude-code-exporter
        image: python:3.11-slim
        command: ["python3", "/app/claude_code_exporter.py"]
        ports:
        - containerPort: 9403
        volumeMounts:
        - name: script
          mountPath: /app
        - name: proc
          mountPath: /host/proc
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: script
        configMap:
          name: claude-code-exporter-script
          defaultMode: 0755
      - name: proc
        hostPath:
          path: /proc
---
apiVersion: v1
kind: Service
metadata:
  name: claude-code-exporter
  namespace: monitoring
spec:
  selector:
    app: claude-code-exporter
  ports:
  - name: metrics
    port: 9403
    targetPort: 9403
  type: ClusterIP
EOF

# Install dependencies
kubectl exec -n monitoring deployment/claude-code-exporter -- pip install prometheus-client psutil
```

---

## Dashboard Configuration

### 1. Deploy System Overview Dashboard

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: system-overview-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  system-overview-dashboard.json: |
    {
      "id": null,
      "uid": "system-overview",
      "title": "ODIN System Overview",
      "tags": ["odin", "overview", "system"],
      "style": "dark",
      "timezone": "browser",
      "refresh": "30s",
      "panels": [
        {
          "id": 1,
          "title": "System Status",
          "type": "stat",
          "targets": [
            {"expr": "up{job=\"prometheus\"}", "legendFormat": "Prometheus", "refId": "A"},
            {"expr": "up{job=\"alertmanager\"}", "legendFormat": "AlertManager", "refId": "B"},
            {"expr": "up{job=\"node-exporter\"}", "legendFormat": "Node Exporter", "refId": "C"},
            {"expr": "up{job=\"power-exporter\"}", "legendFormat": "Power Exporter", "refId": "D"},
            {"expr": "up{job=\"process-exporter\"}", "legendFormat": "Process Exporter", "refId": "E"},
            {"expr": "up{job=\"claude-code-exporter\"}", "legendFormat": "Claude Code Exporter", "refId": "F"}
          ],
          "gridPos": {"h": 4, "w": 12, "x": 0, "y": 0}
        },
        {
          "id": 2,
          "title": "GPU Status",
          "type": "stat",
          "targets": [
            {"expr": "nvidia_gpu_temperature_celsius", "legendFormat": "GPU Temp °C", "refId": "A"},
            {"expr": "nvidia_gpu_power_draw_watts", "legendFormat": "Power Draw W", "refId": "B"},
            {"expr": "nvidia_gpu_utilization_percent", "legendFormat": "GPU Usage %", "refId": "C"}
          ],
          "gridPos": {"h": 4, "w": 12, "x": 12, "y": 0}
        },
        {
          "id": 3,
          "title": "CPU & Memory Usage",
          "type": "timeseries",
          "targets": [
            {"expr": "(1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))) * 100", "legendFormat": "CPU %", "refId": "A"},
            {"expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100", "legendFormat": "Memory %", "refId": "B"}
          ],
          "gridPos": {"h": 8, "w": 24, "x": 0, "y": 4}
        }
      ]
    }
EOF
```

### 2. Deploy Additional Dashboards

```bash
# Simple Logs Dashboard
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: simple-logs-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  simple-logs-dashboard.json: |
    {
      "id": null,
      "uid": "simple-logs",
      "title": "ODIN Simple Logs",
      "tags": ["odin", "logs"],
      "panels": [
        {
          "id": 1,
          "title": "Recent Logs",
          "type": "logs",
          "targets": [
            {
              "expr": "{namespace=\"monitoring\"}",
              "refId": "A",
              "datasource": {
                "type": "loki",
                "uid": "loki"
              }
            }
          ],
          "gridPos": {"h": 20, "w": 24, "x": 0, "y": 0}
        }
      ]
    }
EOF
```

---

## Alerting Setup

### 1. Deploy GPU Alert Rules

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: gpu-alert-rules
  namespace: monitoring
data:
  gpu-alerts.yaml: |
    groups:
    - name: gpu_alerts
      interval: 30s
      rules:
      - alert: GPUHighTemperature
        expr: nvidia_gpu_temperature_celsius > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "GPU temperature high"
          description: "GPU {{ $labels.gpu }} temperature is {{ $value }}°C"
      
      - alert: GPUCriticalTemperature
        expr: nvidia_gpu_temperature_celsius > 87
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "GPU temperature critical"
          description: "GPU {{ $labels.gpu }} temperature is {{ $value }}°C - Thermal throttling imminent"
      
      - alert: GPUHighPowerDraw
        expr: nvidia_gpu_power_draw_watts > 350
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GPU power consumption high"
          description: "GPU {{ $labels.gpu }} power draw is {{ $value }}W"
EOF

# Apply to Prometheus
kubectl create configmap prometheus-rules --from-file=/tmp/gpu-alerts.yaml -n monitoring --dry-run=client -o yaml | kubectl apply -f -
```

---

## Verification & Testing

### 1. Verify All Components

```bash
# Check all pods are running
kubectl get pods -n monitoring

# Check services
kubectl get svc -n monitoring

# Test GPU metrics
curl http://localhost:31493/api/v1/query?query=nvidia_gpu_temperature_celsius

# Access UIs
echo "Prometheus: http://localhost:31493"
echo "Grafana: http://localhost:31494 (admin/admin)"
echo "AlertManager: http://localhost:31495"
```

### 2. Test GPU Monitoring

```bash
# Run GPU stress test
kubectl run gpu-test --rm -it --image=nvidia/cuda:11.8.0-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 \
  --overrides='{"spec":{"runtimeClassName":"nvidia"}}' \
  -- nvidia-smi -l 1

# Watch GPU metrics in Grafana
```

---

## Backup & Maintenance

### 1. Setup Dashboard Backup

```bash
# Create backup script
cat > /home/$USER/odin-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/home/$USER/odin-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup dashboards
kubectl get configmaps -n monitoring -l grafana_dashboard=1 -o yaml > "$BACKUP_DIR/dashboards.yaml"

# Backup configurations
kubectl get configmaps -n monitoring -o yaml > "$BACKUP_DIR/configmaps.yaml"

echo "Backup completed: $BACKUP_DIR"
EOF

chmod +x /home/$USER/odin-backup.sh
```

### 2. Setup Monitoring

```bash
# Create systemd service for ODIN health check
sudo cat > /etc/systemd/system/odin-health.service << EOF
[Unit]
Description=ODIN Health Check
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/kubectl get pods -n monitoring
Restart=always
RestartSec=300

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable odin-health.service
```

---

## Troubleshooting

### Common Issues and Solutions

**1. GPU Not Detected**
```bash
# Check NVIDIA runtime
docker run --rm --runtime=nvidia nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi

# Check device plugin
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds
```

**2. Prometheus Targets Down**
```bash
# Check service discovery
kubectl get endpoints -n monitoring

# Check pod logs
kubectl logs -n monitoring deployment/prometheus
```

**3. Grafana Not Loading Dashboards**
```bash
# Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring

# Check dashboard ConfigMaps
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

**4. High Resource Usage**
```bash
# Scale down replicas
kubectl scale deployment --all --replicas=0 -n monitoring

# Increase resource limits
kubectl edit deployment <name> -n monitoring
```

### Useful Commands

```bash
# View all ODIN resources
kubectl get all -n monitoring

# Delete and recreate namespace (fresh start)
kubectl delete namespace monitoring
kubectl create namespace monitoring

# Export current configuration
kubectl get all -n monitoring -o yaml > odin-backup.yaml

# Monitor resource usage
kubectl top nodes
kubectl top pods -n monitoring
```

---

## Post-Installation

After successful deployment:

1. **Change Grafana Password**: Login with admin/admin and set a secure password
2. **Configure Email Alerts**: Update AlertManager config with SMTP settings
3. **Setup Backup Cron**: Schedule regular dashboard backups
4. **Monitor Storage**: Watch PV usage and expand as needed
5. **Document Custom Dashboards**: Keep track of any custom modifications

---

## Conclusion

Your ODIN monitoring stack is now deployed and operational on your Razer Blade 18. The system will continuously monitor:

- System resources (CPU, memory, disk, network)
- GPU metrics (temperature, power, utilization)
- Process information (including Claude API usage)
- Application logs
- Container metrics

Access Grafana at `http://localhost:31494` to view all dashboards and begin monitoring your infrastructure.

For updates and additional exporters, refer to the ODIN project documentation in the `/docs` directory.