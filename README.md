# ODIN - Omnipresent Diagnostics and Intelligence Network

[![Status](https://img.shields.io/badge/Status-OPERATIONAL-brightgreen.svg)](.)
[![ML Anomaly Detection](https://img.shields.io/badge/ML%20Anomaly%20Detection-ACTIVE-blue.svg)](.)
[![GPU Support](https://img.shields.io/badge/GPU%20Support-RTX%204080-green.svg)](.)
[![Platform](https://img.shields.io/badge/Platform-K3s%20Ubuntu%2022.04-orange.svg)](.)

## Overview

ODIN is a production-ready, Kubernetes-based monitoring and anomaly detection platform designed for Ubuntu 22.04 systems with NVIDIA RTX GPUs. It combines traditional observability with advanced machine learning for intelligent infrastructure monitoring and security analysis.

### 🚀 **Key Features**

- **📊 Full-Stack Observability**: Metrics, logs, and distributed tracing
- **🤖 ML-Powered Anomaly Detection**: Real-time anomaly scoring using Isolation Forest and statistical analysis
- **🔒 Security Monitoring**: Suspicious process detection and threat pattern matching
- **🎯 GPU-Optimized**: Native NVIDIA RTX monitoring with thermal and power analysis
- **⚡ Production-Ready**: Health checks, auto-recovery, model persistence, and email alerting
- **🔄 Self-Healing**: Automatic model retraining and adaptive baseline learning

## Project Structure

```
ODIN/
├── k8s/                    # Kubernetes manifests
│   ├── base/              # Base configurations (Kustomize)
│   └── overlays/          # Environment-specific overlays
│       ├── dev/           # Development environment
│       └── prod/          # Production environment
├── helm/                   # Helm charts
│   ├── charts/            # ODIN Helm charts
│   └── values/            # Environment-specific values
├── ci-cd/                 # CI/CD configurations
│   ├── jenkins/           # Jenkins pipelines
│   └── github-actions/    # GitHub Actions workflows
├── scripts/               # Automation scripts
├── tests/                 # Test suites
│   ├── unit/             # Unit tests
│   ├── integration/      # Integration tests
│   └── e2e/              # End-to-end tests
├── docs/                  # Documentation
│   ├── architecture/     # Architecture documentation
│   ├── api/              # API documentation
│   └── runbooks/         # Operational runbooks
├── monitoring/           # Monitoring configurations
│   ├── dashboards/       # Grafana dashboards
│   └── alerts/           # Prometheus alerts
└── issues/               # Issue tracking

```

## Quick Start

### Prerequisites

- Ubuntu 22.04
- NVIDIA GPU with drivers installed
- K3s or K8s cluster
- kubectl configured
- Helm 3.x

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/ODIN.git
cd ODIN

# Install using Helm
helm install odin ./helm/charts/odin -f ./helm/values/dev.yaml

# Or using Kustomize
kubectl apply -k k8s/overlays/dev
```

## Architecture

### Core Monitoring Stack
- **Prometheus**: Metrics collection and storage with 90-day retention
- **Grafana**: Visualization with 15+ specialized dashboards
- **Loki**: Log aggregation with real-time streaming
- **Promtail**: Log collection from pods and system
- **AlertManager**: Alert routing with email notifications
- **Node Exporter**: System metrics collection
- **Power Exporter**: GPU metrics via nvidia-smi (RTX 4080 optimized)
- **cAdvisor**: Container metrics with cgroups v2 support

### ML Anomaly Detection Platform
- **GPU Anomaly Detector** (Port 9405): Hardware-level anomaly detection
  - Real-time GPU temperature and power analysis
  - Isolation Forest algorithm for complex pattern detection
  - Historical baseline learning with 7-day training windows

- **K8s Pod Anomaly Detector** (Port 9406): Container lifecycle monitoring
  - Pod restart frequency analysis
  - Resource usage anomaly detection (CPU, memory, network)
  - OOM kill detection and container behavior analysis
  - Per-namespace statistical thresholds

- **Process Anomaly Detector** (Port 9407): Security-focused process monitoring
  - Suspicious process pattern detection (crypto miners, reverse shells)
  - New/unknown process alerting with whitelist management
  - Resource consumption anomaly detection per process
  - 7 security threat categories with severity classification

### Data Flow
```
Hardware/System → Exporters → Prometheus → ML Detectors → Grafana/AlertManager
                           ↓
                      Loki ← Promtail ← Pod/System Logs
```

## 🔗 **Quick Access**

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | `http://localhost:31494` | Dashboards and visualization (admin/admin) |
| Prometheus | `http://localhost:31493` | Metrics and queries |
| AlertManager | `http://localhost:31495` | Alert management and routing |

### Key Dashboards
- **ODIN System Overview**: Real-time status of all monitoring components
- **ODIN ML Anomaly Detection**: Live anomaly scores and alerts
- **GPU Monitoring**: RTX 4080 temperature, power, and utilization
- **Claude Code API Monitoring**: Development process tracking

## 📈 **Current Status**

### Operational Metrics (Live)
- **📊 15+ Active Dashboards**: Real-time visualization across all layers
- **🎯 25+ Alert Rules**: Comprehensive coverage from thermal to API usage
- **🤖 3-Layer ML Detection**: Hardware, container, and process anomaly detection
- **🔒 7 Security Categories**: Threat detection from crypto miners to privilege escalation
- **⚡ Sub-minute Detection**: Real-time anomaly scoring with 60-120 second intervals
- **📧 Email Alerting**: Automatic notifications for persistent alerts (>15 minutes)

### Health Status
```bash
# Check all ODIN components
kubectl get pods -n monitoring

# View anomaly detection metrics
curl http://localhost:31493/api/v1/query?query=anomaly_score

# Check ML detector health
kubectl exec -n monitoring <anomaly-pod> -- curl http://localhost:8080/health
```

## ⚙️ **Installation & Deployment**

### Prerequisites
- Ubuntu 22.04.5 LTS
- NVIDIA RTX GPU with drivers (535.230.02+)
- K3s cluster (v1.32.5+)
- kubectl configured
- 8GB+ RAM, 4+ CPU cores

### One-Line Deployment
```bash
# Deploy complete ODIN stack
kubectl apply -f https://raw.githubusercontent.com/yourusername/ODIN/main/k8s/
```

### Manual Deployment
```bash
# Clone repository
git clone https://github.com/yourusername/ODIN.git
cd ODIN

# Deploy core monitoring
kubectl apply -f k8s/prometheus-config.yaml
kubectl apply -f k8s/grafana-deployment.yaml
kubectl apply -f k8s/loki.yaml
kubectl apply -f k8s/alertmanager.yaml

# Deploy exporters
kubectl apply -f k8s/power-exporter.yaml
kubectl apply -f k8s/cadvisor.yaml
kubectl apply -f k8s/node-exporter.yaml

# Deploy ML anomaly detection
kubectl apply -f k8s/anomaly-detector-v2.yaml
kubectl apply -f k8s/k8s-pod-anomaly-detector.yaml
kubectl apply -f k8s/process-anomaly-detector.yaml

# Wait for deployment
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
```

## 🚨 **Alert Configuration**

### Email Setup
Configure SMTP settings in AlertManager:
```yaml
# Update alertmanager-email-config.yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'your-email@gmail.com'
  smtp_auth_username: 'your-email@gmail.com'
  smtp_auth_password: 'your-app-password'
```

### Alert Categories
- **🔥 Critical**: GPU thermal limits, container failures, security threats
- **⚠️ Warning**: High resource usage, restart loops, new processes
- **ℹ️ Info**: Model retraining, baseline updates, system changes

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## 📚 **Documentation**

### Core Documentation
- **[CLAUDE.md](CLAUDE.md)**: Complete project guidance and current status
- **[ML Anomaly Detection Guide](docs/ML_ANOMALY_DETECTION_GUIDE.md)**: Algorithm details and configuration
- **[Claude Token Monitoring](docs/CLAUDE_TOKEN_MONITORING.md)**: API usage tracking
- **[Backup & Restore Guide](docs/BACKUP_RESTORE_GUIDE.md)**: Data protection procedures
- **[Monitoring Operations Guide](docs/MONITORING_OPERATIONS_GUIDE.md)**: Day-to-day operations

### Advanced Guides
- **[Gmail SMTP Setup](docs/GMAIL_SMTP_SETUP.md)**: Email notification configuration
- **[Grafana Metrics Setup](docs/GRAFANA_METRICS_SETUP.md)**: Dashboard configuration
- **[LogQL Best Practices](docs/LOGQL_BEST_PRACTICES.md)**: Log query optimization
- **[cAdvisor Race Condition Analysis](docs/CADVISOR_ERROR_FILTER_SUMMARY.md)**: Troubleshooting guide

## 🔧 **Troubleshooting**

### Common Issues

**GPU Metrics Not Available**
```bash
# Check power-exporter status
kubectl get pods -n monitoring -l app=power-exporter
kubectl logs -n monitoring -l app=power-exporter

# Test nvidia-smi access
kubectl exec -n monitoring <power-exporter-pod> -- nvidia-smi
```

**Anomaly Detection Not Working**
```bash
# Check detector health
kubectl exec -n monitoring <anomaly-detector-pod> -- curl localhost:8080/health

# Verify Prometheus connectivity
kubectl exec -n monitoring <anomaly-detector-pod> -- python3 -c "import requests; print(requests.get('http://prometheus:9090/api/v1/targets').status_code)"
```

**High Resource Usage**
```bash
# Check resource consumption
kubectl top pods -n monitoring

# Scale down non-critical components
kubectl scale deployment grafana --replicas=0 -n monitoring
```

### Performance Tuning
- **Memory**: Increase limits for ML detectors if OOM occurs
- **CPU**: Adjust model training intervals (UPDATE_INTERVAL env var)
- **Storage**: Monitor PVC usage for model persistence
- **Network**: Use node-local DNS caching for large clusters

## 🤝 **Contributing**

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Development Setup
```bash
# Local testing with K3d
k3d cluster create odin-test --agents 1
kubectl apply -k k8s/overlays/dev
```

## 📊 **Metrics & APIs**

### Key Metrics
- `anomaly_score`: Real-time anomaly scoring (0-100 scale)
- `nvidia_gpu_temperature_celsius`: GPU thermal monitoring
- `k8s_pod_anomaly_score`: Container behavior analysis
- `process_anomaly_score`: Process security monitoring
- `unusual_process_detected`: Security threat indicators

### Health Endpoints
- `GET /health`: Detailed component health status
- `GET /healthz`: Simple K8s health check
- `GET /ready`: Readiness for traffic

## 📄 **License**

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🙏 **Acknowledgments**

- **Prometheus Community**: Core metrics infrastructure
- **Grafana Labs**: Visualization and logging
- **NVIDIA**: GPU monitoring capabilities
- **Kubernetes**: Container orchestration platform
- **scikit-learn**: Machine learning algorithms