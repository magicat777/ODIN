# Proof of Concept: ODIN Helm Chart with Profile Values

## Overview

This POC demonstrates packaging ODIN as a Helm chart with customizable profiles for different monitoring environments.

## Directory Structure

```
odin-helm/
├── Chart.yaml
├── values.yaml
├── profiles/
│   ├── base.yaml
│   ├── homelab.yaml
│   ├── storage-focus.yaml
│   ├── enterprise.yaml
│   └── gaming-rig.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── namespace.yaml
│   ├── prometheus/
│   │   ├── deployment.yaml
│   │   ├── configmap.yaml
│   │   └── service.yaml
│   ├── grafana/
│   │   ├── deployment.yaml
│   │   ├── dashboards-configmap.yaml
│   │   └── service.yaml
│   ├── exporters/
│   │   ├── node-exporter.yaml
│   │   ├── nvidia-exporter.yaml
│   │   ├── storage-exporter.yaml
│   │   └── custom-exporter.yaml
│   └── dashboards/
│       └── configmap-generator.yaml
└── scripts/
    ├── detect-profile.sh
    └── install.sh
```

## Core Files

### Chart.yaml
```yaml
apiVersion: v2
name: odin-monitoring
description: A flexible monitoring stack with hardware-aware profiles
type: application
version: 1.0.0
appVersion: "2025.05"
keywords:
  - monitoring
  - prometheus
  - grafana
  - observability
maintainers:
  - name: ODIN Team
sources:
  - https://github.com/odin-monitoring/odin
dependencies:
  - name: kube-state-metrics
    version: "5.0.0"
    repository: "https://prometheus-community.github.io/helm-charts"
    condition: kubeStateMetrics.enabled
```

### values.yaml (Base Values)
```yaml
# Default values for odin-monitoring
global:
  profile: "base"
  autoDetect: true
  storageClass: "local-path"
  domain: "monitoring.local"

prometheus:
  enabled: true
  image:
    repository: prom/prometheus
    tag: v2.45.0
  retention: 30d
  scrapeInterval: 30s
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

grafana:
  enabled: true
  image:
    repository: grafana/grafana
    tag: 10.0.0
  adminPassword: "changeme"
  dashboards:
    autoGenerate: true
    profileBased: true

exporters:
  nodeExporter:
    enabled: true
    image: prom/node-exporter:v1.6.0
  
  nvidiaExporter:
    enabled: false
    image: nvidia/dcgm-exporter:3.0.0
    
  storageExporter:
    enabled: false
    type: "snmp"  # or "custom"
    target: ""
    
  customExporters: []

dashboards:
  system:
    - node-overview
    - cpu-memory-details
  storage: []
  gpu: []
  network: []

alerts:
  enabled: true
  profiles:
    base:
      - node-down
      - disk-space-warning
```

### Profile: storage-focus.yaml
```yaml
# Profile optimized for storage monitoring (Isilon, NAS, SAN)
global:
  profile: "storage-focus"

prometheus:
  retention: 90d
  scrapeInterval: 15s
  extraScrapeConfigs: |
    - job_name: 'snmp-storage'
      static_configs:
        - targets:
          - '{{ .Values.storageExporter.target }}'
      metrics_path: /snmp
      params:
        module: [if_mib]

exporters:
  storageExporter:
    enabled: true
    type: "snmp"
    config:
      walk:
        - 1.3.6.1.4.1.12124.1.1  # Isilon OIDs
        - 1.3.6.1.4.1.12124.1.2
        - 1.3.6.1.4.1.12124.2
      metrics:
        - name: isilon_cluster_health
          oid: 1.3.6.1.4.1.12124.1.1.2
        - name: isilon_node_status
          oid: 1.3.6.1.4.1.12124.1.2.1
        - name: isilon_disk_usage
          oid: 1.3.6.1.4.1.12124.2.1
  
  customExporters:
    - name: isilon-api-exporter
      enabled: true
      image: odin/isilon-exporter:latest
      env:
        - name: ISILON_HOST
          value: "{{ .Values.storageExporter.target }}"
        - name: ISILON_USER
          valueFrom:
            secretKeyRef:
              name: isilon-creds
              key: username

dashboards:
  storage:
    - isilon-overview
    - storage-performance
    - capacity-planning
    - iops-latency
  network:
    - storage-network-flow

alerts:
  profiles:
    storage:
      - isilon-node-down
      - storage-capacity-critical
      - high-latency-warning
      - disk-failure-predicted
```

### Profile: gaming-rig.yaml
```yaml
# Profile for gaming systems with GPU monitoring
global:
  profile: "gaming-rig"

exporters:
  nvidiaExporter:
    enabled: true
    runtimeClass: nvidia
  
  customExporters:
    - name: razer-exporter
      enabled: true
      image: odin/razer-exporter:latest
      hostPID: true
      env:
        - name: RAZER_DEVICE
          value: "auto-detect"
    
    - name: game-launcher-exporter
      enabled: true
      image: odin/game-launcher-exporter:latest

dashboards:
  gpu:
    - nvidia-overview
    - gpu-thermals
    - cuda-utilization
  system:
    - gaming-performance
    - thermal-management
    - power-consumption

alerts:
  profiles:
    gaming:
      - gpu-thermal-critical
      - gpu-memory-exhausted
      - power-limit-throttling
```

## Deployment Scripts

### scripts/detect-profile.sh
```bash
#!/bin/bash
# Auto-detect appropriate profile based on system

detect_profile() {
  local PROFILE="base"
  
  # Check for GPU
  if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU detected"
    PROFILE="gaming-rig"
  fi
  
  # Check for storage systems
  if ping -c1 -W1 isilon.local &> /dev/null 2>&1 || \
     [ -f /etc/snmp/snmpd.conf ]; then
    echo "Storage system detected"
    PROFILE="storage-focus"
  fi
  
  # Check for Kubernetes cluster size
  if [ "$(kubectl get nodes --no-headers 2>/dev/null | wc -l)" -gt 5 ]; then
    echo "Large cluster detected"
    PROFILE="enterprise"
  fi
  
  # Check for specific hardware
  if dmidecode 2>/dev/null | grep -qi "razer"; then
    echo "Razer hardware detected"
    PROFILE="gaming-rig"
  fi
  
  echo "Recommended profile: $PROFILE"
  export ODIN_PROFILE=$PROFILE
}

detect_profile
```

### scripts/install.sh
```bash
#!/bin/bash
# ODIN Helm installation script

set -e

NAMESPACE="monitoring"
RELEASE="odin"
PROFILE="${ODIN_PROFILE:-base}"

# Detect profile if not set
if [ "$PROFILE" == "base" ] && [ "$1" != "--no-detect" ]; then
  source ./scripts/detect-profile.sh
  PROFILE=$ODIN_PROFILE
fi

echo "Installing ODIN with profile: $PROFILE"

# Create namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add helm repo dependencies
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install with profile
helm upgrade --install $RELEASE . \
  --namespace $NAMESPACE \
  --values values.yaml \
  --values profiles/${PROFILE}.yaml \
  --wait

echo "ODIN deployed successfully!"
echo "Access Grafana at: http://localhost:3000"
kubectl port-forward -n $NAMESPACE svc/odin-grafana 3000:3000 &
```

## Template Examples

### templates/exporters/custom-exporter.yaml
```yaml
{{- range .Values.exporters.customExporters }}
{{- if .enabled }}
---
apiVersion: apps/v1
kind: {{ .kind | default "DaemonSet" }}
metadata:
  name: {{ .name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    app.kubernetes.io/name: {{ .name }}
    app.kubernetes.io/instance: {{ $.Release.Name }}
    app.kubernetes.io/component: exporter
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .name }}
      app.kubernetes.io/instance: {{ $.Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ .name }}
        app.kubernetes.io/instance: {{ $.Release.Name }}
    spec:
      {{- if .hostPID }}
      hostPID: true
      {{- end }}
      {{- if .hostNetwork }}
      hostNetwork: true
      {{- end }}
      {{- if .runtimeClass }}
      runtimeClassName: {{ .runtimeClass }}
      {{- end }}
      containers:
      - name: exporter
        image: {{ .image }}
        {{- if .env }}
        env:
{{ toYaml .env | indent 8 }}
        {{- end }}
        ports:
        - name: metrics
          containerPort: {{ .port | default 9100 }}
        {{- if .resources }}
        resources:
{{ toYaml .resources | indent 10 }}
        {{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    app.kubernetes.io/name: {{ .name }}
    app.kubernetes.io/instance: {{ $.Release.Name }}
spec:
  ports:
  - name: metrics
    port: {{ .port | default 9100 }}
    targetPort: metrics
  selector:
    app.kubernetes.io/name: {{ .name }}
    app.kubernetes.io/instance: {{ $.Release.Name }}
{{- end }}
{{- end }}
```

## Usage Examples

### 1. Basic Installation
```bash
# Install with auto-detection
./scripts/install.sh

# Install with specific profile
helm install odin ./odin-helm -f profiles/storage-focus.yaml
```

### 2. Custom Storage Monitoring
```bash
# Create custom values
cat > custom-storage.yaml <<EOF
storageExporter:
  target: "192.168.1.100"
  type: "snmp"
  community: "public"
  
dashboards:
  storage:
    - isilon-overview
    - custom-nas-metrics
    
customExporters:
  - name: storage-api-exporter
    enabled: true
    image: myregistry/storage-exporter:latest
    env:
      - name: API_ENDPOINT
        value: "https://storage.local/api"
EOF

# Install with storage profile + custom values
helm install odin ./odin-helm \
  -f profiles/storage-focus.yaml \
  -f custom-storage.yaml
```

### 3. Multi-Profile Deployment
```bash
# Combine profiles for hybrid environment
helm install odin ./odin-helm \
  -f profiles/base.yaml \
  -f profiles/storage-focus.yaml \
  -f profiles/gaming-rig.yaml \
  --set exporters.nvidiaExporter.enabled=true \
  --set exporters.storageExporter.enabled=true
```

## Dashboard Generation

The Helm chart includes a dashboard generator that creates Grafana dashboards based on the selected profile and detected hardware:

```yaml
# templates/dashboards/configmap-generator.yaml
{{- if .Values.grafana.dashboards.autoGenerate }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-dashboard-generator
  namespace: {{ .Release.Namespace }}
data:
  generate.sh: |
    #!/bin/bash
    PROFILE="{{ .Values.global.profile }}"
    
    case $PROFILE in
      "storage-focus")
        # Generate storage-specific dashboards
        cat > /dashboards/storage-overview.json <<'EOF'
    {
      "dashboard": {
        "title": "Storage Overview - {{ .Values.storageExporter.target }}",
        "panels": [
          {
            "title": "Cluster Health",
            "targets": [{"expr": "isilon_cluster_health"}]
          }
        ]
      }
    }
    EOF
        ;;
      "gaming-rig")
        # Generate gaming-specific dashboards
        ;;
    esac
{{- end }}
```

## Advantages of This Approach

1. **Standardized Deployment**: Uses Kubernetes-native packaging
2. **Profile Inheritance**: Can layer profiles for complex environments
3. **Version Control**: Easy to track changes and rollback
4. **Community Ecosystem**: Leverage existing Helm charts
5. **GitOps Ready**: Works with ArgoCD, Flux, etc.
6. **Scalable**: From single-node to large clusters

## Next Steps

1. Create the actual Helm chart structure
2. Build and publish custom exporter images
3. Create a dashboard library for each profile
4. Set up CI/CD for chart testing and publication
5. Create an operator for advanced automation