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

## Quick Start

### Prerequisites

- Ubuntu 22.04
- NVIDIA GPU with drivers installed
- K3s or K8s cluster
- kubectl configured

### Installation

```bash
# Clone the repository
git clone https://github.com/magicat777/ODIN.git
cd ODIN

# Deploy ODIN stack
kubectl apply -f k8s/
```

## 🔗 **Quick Access**

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | `http://localhost:31494` | Dashboards and visualization (admin/admin) |
| Prometheus | `http://localhost:31493` | Metrics and queries |
| AlertManager | `http://localhost:31495` | Alert management and routing |

## Architecture

### Core Components
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization with 15+ dashboards
- **Loki**: Log aggregation
- **AlertManager**: Alert routing with email notifications
- **ML Detectors**: 3-layer anomaly detection system

### ML Anomaly Detection
- **GPU Anomaly Detector** (Port 9405): Hardware monitoring
- **K8s Pod Anomaly Detector** (Port 9406): Container lifecycle analysis
- **Process Anomaly Detector** (Port 9407): Security threat detection

## 📄 **License**

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.