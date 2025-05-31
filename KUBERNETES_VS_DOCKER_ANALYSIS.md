# Kubernetes vs Docker for ODIN Monitoring Stack

## Overview

This document explains how Kubernetes would function in the Razer Blade 18 environment, its differences from Docker/Docker Compose, and how it would solve the networking challenges we encountered.

## How Kubernetes Would Function in This Environment

### Single-Node Kubernetes Options

For a Razer Blade 18 laptop, we'd use a lightweight Kubernetes distribution:

1. **K3s** (Recommended)
   - Lightweight (~40MB binary)
   - Low resource overhead
   - Built-in local storage provider
   - Integrated ingress controller

2. **MicroK8s**
   - Snap-based installation
   - GPU addon available
   - Built-in observability stack

3. **Kind (Kubernetes in Docker)**
   - Runs Kubernetes inside Docker containers
   - Good for development/testing

### Architecture in Kubernetes

```yaml
# Example Kubernetes deployment
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
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
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
  - port: 9090
    targetPort: 9090
```

## Key Differences from Docker

### 1. **Declarative vs Imperative**

**Docker Compose:**
```yaml
services:
  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
```

**Kubernetes:**
```yaml
# ConfigMap for configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
---
# Deployment references ConfigMap
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
spec:
  template:
    spec:
      containers:
      - name: prometheus
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
```

### 2. **Service Discovery**

**Docker:** Manual container linking or custom networks
**Kubernetes:** Built-in DNS-based service discovery

```yaml
# Any pod can reach prometheus at:
# prometheus.monitoring.svc.cluster.local:9090
# Or simply: prometheus:9090 (within same namespace)
```

### 3. **Resource Management**

**Docker:** Basic CPU/memory limits
**Kubernetes:** Sophisticated resource quotas and limits

```yaml
resources:
  requests:
    memory: "500Mi"
    cpu: "250m"
    nvidia.com/gpu: 1  # GPU request
  limits:
    memory: "1Gi"
    cpu: "500m"
```

### 4. **Configuration Management**

**Docker:** Environment variables or mounted files
**Kubernetes:** ConfigMaps and Secrets

```yaml
# ConfigMap for non-sensitive data
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
data:
  prometheus.yml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus:9090
---
# Secret for sensitive data
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
type: Opaque
data:
  password: YWRtaW4=  # base64 encoded
```

## How Kubernetes Solves Our Networking Challenges

### 1. **Consistent Service Discovery**

**Problem:** Containers couldn't find host services, `host.docker.internal` didn't work
**Kubernetes Solution:** Every service gets a DNS name automatically

```yaml
# Prometheus can scrape targets using service names:
scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
    - targets: ['node-exporter:9100']
  
  - job_name: 'nvidia-exporter'
    static_configs:
    - targets: ['nvidia-exporter:9400']
  
  - job_name: 'grafana'
    static_configs:
    - targets: ['grafana:3000']
```

### 2. **Network Policies**

**Problem:** No control over container-to-container communication
**Kubernetes Solution:** Fine-grained network policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-ingress
spec:
  podSelector:
    matchLabels:
      app: prometheus
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: grafana
    ports:
    - port: 9090
```

### 3. **Ingress Management**

**Problem:** Port conflicts and complex port mappings
**Kubernetes Solution:** Ingress controller handles routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring-ingress
spec:
  rules:
  - host: grafana.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
  - host: prometheus.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 9090
```

### 4. **Service Mesh Capabilities**

**Problem:** No visibility into service-to-service communication
**Kubernetes Solution:** Can add service mesh (Linkerd, Istio)

```yaml
# Automatic mTLS, traffic management, observability
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  annotations:
    linkerd.io/inject: enabled
```

## Specific Advantages for ODIN Stack

### 1. **GPU Support**

```yaml
# NVIDIA GPU support with device plugin
apiVersion: v1
kind: Pod
metadata:
  name: nvidia-exporter
spec:
  containers:
  - name: nvidia-exporter
    image: nvidia/dcgm-exporter:latest
    resources:
      limits:
        nvidia.com/gpu: 1
```

### 2. **Persistent Storage**

```yaml
# Automatic volume provisioning
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
```

### 3. **Health Checks and Self-Healing**

```yaml
livenessProbe:
  httpGet:
    path: /-/healthy
    port: 9090
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /-/ready
    port: 9090
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 4. **Rolling Updates**

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

## Complete ODIN Stack in Kubernetes

### Namespace and Core Services

```yaml
# monitoring-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
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
        image: prom/prometheus:latest
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus/'
          - '--web.console.libraries=/etc/prometheus/console_libraries'
          - '--web.console.templates=/etc/prometheus/consoles'
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: storage
          mountPath: /prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: storage
        persistentVolumeClaim:
          claimName: prometheus-pvc
---
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
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: grafana-admin
              key: password
        volumeMounts:
        - name: datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: dashboards
          mountPath: /etc/grafana/provisioning/dashboards
        - name: storage
          mountPath: /var/lib/grafana
      volumes:
      - name: datasources
        configMap:
          name: grafana-datasources
      - name: dashboards
        configMap:
          name: grafana-dashboards
      - name: storage
        persistentVolumeClaim:
          claimName: grafana-pvc
```

### Service Definitions

```yaml
# services.yaml
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
```

### Prometheus Configuration via ConfigMap

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
    
    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - monitoring
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
    
    - job_name: 'kubernetes-services'
      kubernetes_sd_configs:
      - role: service
        namespaces:
          names:
          - monitoring
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

## Migration Path from Docker to Kubernetes

### Phase 1: Setup K3s
```bash
# Install K3s with GPU support
curl -sfL https://get.k3s.io | sh -s - \
  --docker \
  --disable traefik \
  --kubelet-arg="feature-gates=DevicePlugins=true"

# Install NVIDIA device plugin
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.13.0/nvidia-device-plugin.yml
```

### Phase 2: Deploy Monitoring Stack
```bash
# Create namespace
kubectl create namespace monitoring

# Deploy using Helm (easier management)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts

# Install Prometheus Operator (manages Prometheus/AlertManager)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Install Loki Stack
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true
```

### Phase 3: Migrate Custom Exporters
```bash
# Build and push custom exporter images
docker build -t localhost:5000/nvidia-exporter:latest .
docker push localhost:5000/nvidia-exporter:latest

# Deploy custom exporters
kubectl apply -f nvidia-exporter-deployment.yaml
```

## Conclusion

Kubernetes would resolve our networking challenges through:

1. **Built-in Service Discovery**: No more `host.docker.internal` issues
2. **Consistent Networking Model**: Same whether on laptop or cloud
3. **Declarative Configuration**: Version-controlled, reproducible deployments
4. **Self-Healing**: Automatic container restarts and health monitoring
5. **Resource Isolation**: Better resource management and guarantees
6. **Scalability**: Easy to scale services up/down
7. **Rolling Updates**: Zero-downtime deployments

The main trade-off is increased complexity for initial setup, but this is offset by:
- Better long-term maintainability
- Industry-standard patterns
- Extensive ecosystem support
- Unified configuration management
- Production-ready features out of the box

For the ODIN monitoring stack, Kubernetes would provide a stable, scalable foundation that eliminates the networking issues we encountered with Docker's context switching.