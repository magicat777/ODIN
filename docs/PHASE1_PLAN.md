# Phase 1: Foundation & Infrastructure Implementation Plan

## Overview
Phase 1 establishes the foundational Kubernetes infrastructure with GPU support, persistent storage, and basic CI/CD pipeline.

## Prerequisites Checklist
- [ ] Ubuntu 22.04 installed and updated
- [ ] NVIDIA drivers installed and functional (verify with `nvidia-smi`)
- [ ] Docker or containerd installed
- [ ] Git repository access configured
- [ ] Minimum 32GB RAM and 100GB storage available

## Sprint 1: K3s and GPU Infrastructure (Week 1)

### Day 1-2: K3s Installation
```bash
# Task ODIN-001: Install K3s
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb

# Configure kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

### Day 2-3: NVIDIA Runtime Configuration
```bash
# Task ODIN-002: Configure NVIDIA Container Runtime
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure containerd for K3s
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart k3s
```

### Day 3-4: GPU Device Plugin
```yaml
# Task ODIN-003: Deploy NVIDIA Device Plugin
# nvidia-device-plugin.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      priorityClassName: "system-node-critical"
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.14.0
        name: nvidia-device-plugin-ctr
        env:
        - name: FAIL_ON_INIT_ERROR
          value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
```

### Day 4-5: Storage and Namespace Setup
```yaml
# Task ODIN-004: Create Storage Class
# local-storage.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete

---
# Task ODIN-005: Create Monitoring Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
```

## Sprint 2: Helm, Kustomize, and CI/CD (Week 2)

### Day 6-7: Helm Chart Structure
```bash
# Task ODIN-009: Create Helm Chart
helm create odin-monitoring

# Directory structure
odin-monitoring/
├── Chart.yaml
├── values.yaml
├── values-dev.yaml
├── values-prod.yaml
├── templates/
│   ├── namespace.yaml
│   ├── rbac.yaml
│   ├── prometheus/
│   ├── grafana/
│   └── exporters/
└── charts/
```

### Day 8-9: Kustomize Configuration
```yaml
# Task ODIN-011: Kustomize Base
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - rbac.yaml
  - storage.yaml

---
# Task ODIN-012: Dev Overlay
# k8s/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

patchesStrategicMerge:
  - prometheus-patch.yaml
  - grafana-patch.yaml

configMapGenerator:
  - name: env-config
    literals:
      - ENVIRONMENT=dev
      - LOG_LEVEL=debug
```

### Day 9-10: CI/CD and Testing
```makefile
# Task ODIN-013: Makefile
.PHONY: help install test deploy clean

help:
	@echo "ODIN Makefile Commands:"
	@echo "  install     - Install dependencies"
	@echo "  test        - Run tests"
	@echo "  deploy-dev  - Deploy to dev environment"
	@echo "  deploy-prod - Deploy to production"
	@echo "  clean       - Clean up resources"

install:
	kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update

test:
	pytest tests/
	helm lint helm/charts/odin-monitoring
	kubectl apply --dry-run=client -k k8s/overlays/dev

deploy-dev:
	kubectl apply -k k8s/overlays/dev
	helm upgrade --install odin ./helm/charts/odin-monitoring -f helm/values/dev.yaml

clean:
	kubectl delete -k k8s/overlays/dev
	helm uninstall odin
```

## Validation Tests

### GPU Access Test
```yaml
# Task ODIN-008: GPU Validation
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-test
    image: nvcr.io/nvidia/cuda:11.8.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
```

### Smoke Test Script
```python
# Task ODIN-015: tests/smoke_test.py
import subprocess
import time
import requests

def test_k3s_running():
    """Test that K3s is running"""
    result = subprocess.run(['kubectl', 'get', 'nodes'], capture_output=True)
    assert result.returncode == 0
    assert 'Ready' in result.stdout.decode()

def test_gpu_available():
    """Test that GPU is available in cluster"""
    result = subprocess.run(
        ['kubectl', 'get', 'nodes', '-o', 'json'],
        capture_output=True
    )
    assert result.returncode == 0
    output = result.stdout.decode()
    assert 'nvidia.com/gpu' in output

def test_monitoring_namespace():
    """Test that monitoring namespace exists"""
    result = subprocess.run(
        ['kubectl', 'get', 'namespace', 'monitoring'],
        capture_output=True
    )
    assert result.returncode == 0

def test_storage_class():
    """Test that storage class is available"""
    result = subprocess.run(
        ['kubectl', 'get', 'storageclass'],
        capture_output=True
    )
    assert result.returncode == 0
    assert 'local-path' in result.stdout.decode()
```

## Deliverables Checklist

### Infrastructure
- [ ] K3s cluster operational
- [ ] GPU support verified
- [ ] Storage class configured
- [ ] Monitoring namespace created
- [ ] RBAC policies applied

### CI/CD
- [ ] Helm charts created
- [ ] Kustomize overlays configured
- [ ] Makefile with common commands
- [ ] GitHub Actions workflow
- [ ] Pre-commit hooks configured

### Documentation
- [ ] Installation guide
- [ ] Architecture diagram
- [ ] Troubleshooting guide
- [ ] Test procedures

### Testing
- [ ] GPU access validated
- [ ] Smoke tests passing
- [ ] Helm chart linting passing
- [ ] Dry-run deployments successful

## Success Criteria
1. K3s cluster running with `kubectl get nodes` showing Ready
2. GPU available with `nvidia.com/gpu` in node capacity
3. Test pod can access GPU and run `nvidia-smi`
4. Storage class allows PVC creation
5. All smoke tests passing
6. CI/CD pipeline triggered on git push

## Rollback Plan
1. Save current system state: `kubectl get all -A -o yaml > backup.yaml`
2. If K3s fails: `sudo /usr/local/bin/k3s-uninstall.sh`
3. If GPU fails: Revert NVIDIA runtime configuration
4. Document all issues in `TROUBLESHOOTING.md`

## Next Phase Prerequisites
Before proceeding to Phase 2:
1. All Phase 1 deliverables completed
2. GPU metrics visible in test pods
3. Persistent volumes tested and working
4. Team trained on Helm/Kustomize usage
5. CI/CD pipeline validated