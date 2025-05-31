# Claude Deployment Guide for ODIN

## Overview

This guide provides step-by-step instructions for Claude to deploy the ODIN monitoring stack on Kubernetes. All commands are designed to work without sudo privileges.

## Prerequisites Check

Before starting, verify these prerequisites:

```bash
# Check GPU drivers
nvidia-smi

# Check if K3s is installed
kubectl version --client

# Check available disk space (need at least 100GB)
df -h /home/magicat777

# Check current directory
cd /home/magicat777/projects/ODIN
pwd
```

## Phase 1: Foundation Setup

### Step 1.1: Initialize K3s (if not already done)
```bash
# Check if K3s is already running
kubectl get nodes

# If not, request admin to run:
# curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --disable traefik --disable servicelb
```

### Step 1.2: Setup Kubernetes Configuration
```bash
# Configure kubectl (no sudo needed)
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Test access
kubectl get nodes
```

### Step 1.3: Deploy NVIDIA Device Plugin
```bash
# Apply NVIDIA device plugin
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# Wait for it to be ready
kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=60s

# Verify GPU is available
kubectl describe nodes | grep -A 5 "nvidia.com/gpu"
```

### Step 1.4: Create Monitoring Namespace and Storage
```bash
# Create namespace
kubectl create namespace monitoring

# Create directories for persistent volumes (request admin if needed)
# sudo mkdir -p /var/lib/odin/{prometheus,grafana,loki,alertmanager}
# sudo chown -R $USER:$USER /var/lib/odin

# Create storage class
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
```

### Step 1.5: Validate Phase 1
```bash
# Run GPU test
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:11.8.0-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 -- nvidia-smi

# Check namespace
kubectl get namespace monitoring
```

## Phase 2: Core Monitoring Stack

### Step 2.1: Create Prometheus Configuration
```bash
# Create Prometheus config directory
mkdir -p k8s/base/prometheus

# Create Prometheus ConfigMap
cat > k8s/base/prometheus/prometheus-config.yaml << 'EOF'
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
      
      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
          - role: node
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
      
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
EOF

kubectl apply -f k8s/base/prometheus/prometheus-config.yaml
```

### Step 2.2: Deploy Prometheus
```bash
# Create Prometheus PVC
cat <<EOF | kubectl apply -f -
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
  storageClassName: local-path
EOF

# Create Prometheus Deployment
cat <<EOF | kubectl apply -f -
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
          - '--web.enable-lifecycle'
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
EOF

# Create Service
cat <<EOF | kubectl apply -f -
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
EOF
```

### Step 2.3: Deploy Grafana
```bash
# Create Grafana secret
kubectl create secret generic grafana-secret \
  --from-literal=admin-password=admin \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Create Grafana PVC
cat <<EOF | kubectl apply -f -
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
  storageClassName: local-path
EOF

# Deploy Grafana (use the configuration from PHASE2_PLAN.md)
kubectl apply -f k8s/base/grafana/
```

### Step 2.4: Deploy Exporters
```bash
# Deploy Node Exporter
kubectl apply -f k8s/base/exporters/node-exporter.yaml

# Deploy cAdvisor
kubectl apply -f k8s/base/exporters/cadvisor.yaml

# Deploy NVIDIA DCGM Exporter
kubectl apply -f k8s/base/exporters/nvidia-dcgm-exporter.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
```

### Step 2.5: Validate Phase 2
```bash
# Check all pods are running
kubectl get pods -n monitoring

# Test Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
sleep 5
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job:.job, health:.health}'

# Kill port forward
pkill -f "port-forward.*9090"
```

## Phase 3: Logging and Alerting

### Step 3.1: Deploy Loki
```bash
# Apply Loki configuration from PHASE3_PLAN.md
kubectl apply -f k8s/base/loki/

# Wait for Loki to be ready
kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=300s
```

### Step 3.2: Deploy Promtail
```bash
# Apply Promtail configuration
kubectl apply -f k8s/base/promtail/

# Check Promtail is running on all nodes
kubectl get pods -n monitoring -l name=promtail
```

### Step 3.3: Deploy AlertManager
```bash
# Apply AlertManager configuration
kubectl apply -f k8s/base/alertmanager/

# Create alert rules
kubectl apply -f k8s/base/prometheus/alert-rules.yaml

# Restart Prometheus to load new configuration
kubectl rollout restart deployment/prometheus -n monitoring
```

## Phase 4: Advanced Features

### Step 4.1: Install Linkerd (Optional)
```bash
# Install Linkerd CLI
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Check pre-requisites
linkerd check --pre

# Install Linkerd (requires admin to run these):
# linkerd install --crds | kubectl apply -f -
# linkerd install | kubectl apply -f -
# linkerd check
```

### Step 4.2: Deploy Custom Exporters
```bash
# Deploy custom exporter from PHASE4_PLAN.md
kubectl apply -f k8s/base/exporters/custom-exporter-deployment.yaml
```

### Step 4.3: Setup Automated Backups
```bash
# Create backup script
chmod +x scripts/backup-monitoring.sh

# Create backup CronJob
kubectl apply -f k8s/base/backup/backup-cronjob.yaml
```

## Phase 5: Production Readiness

### Step 5.1: Generate Certificates
```bash
# Run certificate generation script
chmod +x scripts/generate-certs.sh
./scripts/generate-certs.sh

# Create TLS secrets
for service in prometheus grafana alertmanager loki; do
  kubectl create secret tls ${service}-tls \
    --cert=${HOME}/odin-certs/${service}.pem \
    --key=${HOME}/odin-certs/${service}-key.pem \
    -n monitoring --dry-run=client -o yaml | kubectl apply -f -
done
```

### Step 5.2: Apply Security Policies
```bash
# Apply network policies
kubectl apply -f k8s/base/security/network-policies.yaml

# Apply RBAC policies
kubectl apply -f k8s/base/security/prometheus-rbac.yaml
```

## Validation and Testing

### Run Integration Tests
```bash
# Make test script executable
chmod +x tests/final_integration_test.py

# Run tests
python3 tests/final_integration_test.py

# Check test report
cat test-report.md
```

### Access Grafana
```bash
# Get NodePort
GRAFANA_PORT=$(kubectl get svc grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')
echo "Grafana available at: http://localhost:${GRAFANA_PORT}"
echo "Login: admin / admin"
```

## Troubleshooting Commands

### Check Pod Logs
```bash
# View logs for any pod
kubectl logs -n monitoring deployment/prometheus
kubectl logs -n monitoring deployment/grafana
kubectl logs -n monitoring daemonset/promtail
```

### Check Resource Usage
```bash
# View resource consumption
kubectl top pods -n monitoring
kubectl top nodes
```

### Debug Networking
```bash
# Test service connectivity
kubectl exec -n monitoring deployment/prometheus -- wget -O- http://grafana:3000/api/health
kubectl exec -n monitoring deployment/grafana -- wget -O- http://prometheus:9090/-/healthy
```

### Emergency Rollback
```bash
# Scale down all deployments
kubectl scale deployment --all -n monitoring --replicas=0

# Delete namespace (complete removal)
# kubectl delete namespace monitoring
```

## Daily Operations

### Health Check
```bash
# Run daily health check
make status

# Check specific component
kubectl describe pod -n monitoring -l app=prometheus
```

### Backup
```bash
# Manual backup
./scripts/backup-monitoring.sh

# List backups
ls -la ~/odin-backups/
```

### Update Configuration
```bash
# Update Prometheus config
kubectl edit configmap prometheus-config -n monitoring

# Reload Prometheus
kubectl rollout restart deployment/prometheus -n monitoring
```

## Important Notes for Claude

1. **Never use sudo** - All commands work with user permissions
2. **Always check prerequisites** - Ensure K3s and GPU drivers are ready
3. **Use kubectl dry-run** - Test changes before applying
4. **Monitor resource usage** - Watch for memory/CPU constraints
5. **Keep backups** - Run backup script before major changes
6. **Document changes** - Update this guide with any modifications

## Quick Command Reference

```bash
# Namespace operations
kubectl get all -n monitoring
kubectl describe pod <pod-name> -n monitoring
kubectl logs <pod-name> -n monitoring

# Port forwarding (for testing)
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Configuration updates
kubectl apply -f <file.yaml>
kubectl rollout restart deployment/<name> -n monitoring

# Troubleshooting
kubectl exec -it -n monitoring deployment/<name> -- /bin/sh
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

## Success Indicators

✅ All pods showing Running status
✅ No restart loops in pod descriptions  
✅ Prometheus targets all UP
✅ Grafana dashboards loading data
✅ GPU metrics visible
✅ Logs searchable in Grafana
✅ Test alerts firing correctly

## Next Steps

1. Review all dashboards in Grafana
2. Configure alert notification channels
3. Set up regular backup verification
4. Document any custom configurations
5. Plan for capacity growth

This completes the Claude deployment guide. Follow these steps sequentially for a successful ODIN deployment!