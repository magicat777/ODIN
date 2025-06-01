# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ODIN (Omnipresent Diagnostics and Intelligence Network) is a comprehensive monitoring stack designed for Ubuntu 22.04 systems with NVIDIA RTX GPUs. The project successfully implements monitoring solutions using Kubernetes (K3s) instead of Docker, providing better networking, service discovery, and production-grade features.

**Current Status: ✅ OPERATIONAL** - Core monitoring stack with advanced ML anomaly detection fully deployed and functional.

## Key Architecture Decisions

1. **Kubernetes over Docker**: The project migrated from Docker Compose to Kubernetes (K3s) to solve networking issues with Docker contexts, particularly around `host.docker.internal` not working on Linux.

2. **Single-Node K3s**: Uses lightweight K3s distribution suitable for development on a Razer Blade 18 laptop while maintaining production-grade patterns.

3. **NVIDIA GPU Support**: Implements NVIDIA device plugin and runtime classes for GPU monitoring and workload support.

## Common Commands

### Kubernetes Management
```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n monitoring

# Apply configurations
kubectl apply -f <filename>.yaml

# Check logs
kubectl logs -n monitoring <pod-name>

# Port forwarding for local access
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Restart deployments
kubectl rollout restart deployment/<name> -n monitoring
```

### Development Workflow
```bash
# Test GPU access
kubectl run gpu-test --rm -it --image=nvidia/cuda:11.8.0-base-ubuntu22.04 --limits=nvidia.com/gpu=1 -- nvidia-smi

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets'

# Query metrics
curl http://localhost:9090/api/v1/query?query=<metric_name>
```

## Project Structure

The project contains documentation and planning files for migrating from Docker to Kubernetes:

- **KUBERNETES_VS_DOCKER_ANALYSIS.md**: Detailed comparison of Kubernetes vs Docker approaches, explaining why K8s solves the networking challenges
- **ODIN_K8S_PROJECT_PLAN.md**: Complete implementation plan with YAML manifests for all monitoring components
- **PROJECT_FAILURE_ANALYSIS.md**: Post-mortem of the Docker deployment failure and recovery strategies

## Key Components

### Core Monitoring Stack (✅ DEPLOYED)
- **Prometheus**: Metrics collection and storage - *OPERATIONAL*
- **Grafana**: Visualization and dashboards - *OPERATIONAL with 15+ dashboards*
- **Loki**: Log aggregation - *OPERATIONAL with live log streams*
- **AlertManager**: Alert routing - *OPERATIONAL with email notifications*
- **Node Exporter**: System metrics - *OPERATIONAL*
- **Power Exporter**: GPU metrics via nvidia-smi - *OPERATIONAL (RTX 4080)*
- **cAdvisor**: Container metrics - *OPERATIONAL*
- **Promtail**: Log collection - *OPERATIONAL collecting pod and system logs*

### Advanced ML Anomaly Detection (✅ DEPLOYED)
- **GPU Anomaly Detector** (Port 9405): ML-powered GPU temperature and power anomaly detection - *OPERATIONAL*
- **K8s Pod Anomaly Detector** (Port 9406): Container lifecycle and resource anomaly detection - *OPERATIONAL*
- **Process Anomaly Detector** (Port 9407): Security-focused process behavior and suspicious activity detection - *OPERATIONAL*
- **Disk Anomaly Detector** (Port 9408): Disk space forecasting and I/O anomaly detection - *OPERATIONAL*
- **Multi-Algorithm Approach**: Isolation Forest, statistical analysis, and linear regression forecasting
- **Real-time Detection**: Sub-minute anomaly scoring with historical baseline learning

### Networking
- All services use Kubernetes DNS for service discovery
- Services communicate via `<service-name>.<namespace>.svc.cluster.local`
- No need for `host.docker.internal` workarounds

### Storage
- Uses local storage class with persistent volumes
- Data stored in `/var/lib/odin/{prometheus,grafana,loki,alertmanager}`

## Important Considerations

1. **GPU Monitoring**: Requires NVIDIA Container Toolkit and device plugin. Uses RuntimeClass `nvidia` for GPU-enabled pods.

2. **Service Discovery**: Kubernetes automatically provides DNS names for all services, eliminating Docker networking issues.

3. **Resource Management**: All deployments include resource requests and limits to ensure stable operation.

4. **Persistent Data**: Uses PersistentVolumeClaims to ensure data survives pod restarts.

5. **Health Checks**: Implements liveness and readiness probes for all services.

## Development Tips

- Always check if NVIDIA runtime is available before deploying GPU workloads
- Use `kubectl wait` commands to ensure services are ready before proceeding
- Monitor resource usage to prevent exhausting laptop resources
- Use ConfigMaps for configuration to enable easy updates without rebuilding images

## Current Implementation Status

### ✅ **Successfully Deployed Components**
1. **Core Monitoring**: Prometheus, Grafana, AlertManager all operational
2. **GPU Monitoring**: Power-exporter with health checks collecting RTX 4080 metrics 
3. **Log Collection**: Loki + Promtail collecting live logs from all pods and system
4. **Dashboards**: 15+ operational dashboards including comprehensive overviews
5. **Service Discovery**: Full Kubernetes DNS resolution working
6. **Claude Code Monitoring**: Process tracking, token usage, and API cost monitoring
7. **Health Monitoring**: Production-ready health checks for all custom exporters
8. **Advanced Alerting**: 25+ alert rules covering thermal, resource, and API usage

### ⚠️ **Known Issues & Workarounds**
1. **NVIDIA DCGM Exporter**: Replaced with power-exporter due to NVML library compatibility
2. **Loki Datasource**: Requires full FQDN (`loki.monitoring.svc.cluster.local:3100`) for Grafana connectivity
3. **AlertManager Webhook**: Currently failing to connect to external webhook (expected behavior)

### 📊 **Access URLs**
- **Grafana**: `http://localhost:31494` (admin/admin)
- **Prometheus**: `http://localhost:31493` 
- **AlertManager**: `http://localhost:31495`

## ML Anomaly Detection Architecture

### Algorithm Selection
- **Isolation Forest**: Used for complex, multi-dimensional anomalies (GPU metrics, process behavior)
- **Statistical Analysis**: Used for well-understood metrics with clear thresholds (memory, restarts)
- **Hybrid Approach**: Combines both methods for comprehensive coverage

### Detection Layers
1. **Hardware Layer**: GPU temperature, power consumption anomalies
2. **Container Layer**: K8s pod lifecycle, resource usage, restart patterns
3. **Process Layer**: Suspicious process detection, resource consumption anomalies
4. **Security Layer**: Pattern matching for crypto miners, reverse shells, privilege escalation

### Model Persistence & Learning
- Models automatically retrain every 6 hours with 7-day historical data
- Persistent storage ensures models survive pod restarts
- Per-namespace and per-process baseline thresholds
- Adaptive sensitivity based on historical patterns

### 🎯 **Latest Major Achievements**
1. **Production Email Alert System**: Complete webhook-to-email bridge with Gmail SMTP integration
2. **Critical Alert Notifications**: OOM kills, container crashes, and ML anomalies trigger instant emails
3. **Gmail App Password Authentication**: Secure, production-ready email delivery system
4. **Alert Investigation & Cleanup**: Resolved 80+ false alerts and optimized routing rules
5. **Enhanced Pod Monitoring**: Comprehensive container lifecycle and memory monitoring
6. **Advanced AlertManager Configuration**: Component-specific routing with inhibition rules
7. **End-to-End Email Testing**: Verified complete alert-to-email delivery pipeline

### 📊 **Dashboard Inventory**
- **ODIN System Overview**: Unified system status and resource usage
- **ODIN ML Anomaly Detection**: Real-time anomaly scores for GPU, processes, and containers
- **ODIN Simple Logs**: Real-time log streaming from all components
- **Claude Code API Monitoring**: Process metrics and token usage tracking
- **GPU Monitoring Dashboards**: Temperature, power, memory, utilization with anomaly scoring
- **Power & Thermal**: System-wide power consumption and thermal status
- **Network Analysis**: Connection states and traffic patterns
- **Performance Baselines**: Historical performance tracking with ML-based thresholds

### 🔧 **Next Steps**
See ISSUE_TRACKER.md for production readiness items and advanced features.

### 📚 **Additional Documentation**
- **Claude Token Monitoring**: `docs/CLAUDE_TOKEN_MONITORING.md`
- **Health Check Implementation**: Available in exporter configs
- **Alert Rule Documentation**: Available in alert rule ConfigMaps