# ODIN Architecture Guide

## Table of Contents

1. [System Overview](#system-overview)
2. [Core Components](#core-components)
3. [Data Flow Architecture](#data-flow-architecture)
4. [Network Architecture](#network-architecture)
5. [Storage Architecture](#storage-architecture)
6. [Security Architecture](#security-architecture)
7. [High Availability Design](#high-availability-design)
8. [GPU Monitoring Architecture](#gpu-monitoring-architecture)
9. [Service Mesh Integration](#service-mesh-integration)
10. [Deployment Patterns](#deployment-patterns)
11. [Scaling Strategies](#scaling-strategies)
12. [Disaster Recovery](#disaster-recovery)

## System Overview

ODIN (Observability Dashboard for Infrastructure and NVIDIA) is a cloud-native monitoring stack built on Kubernetes, designed to provide comprehensive observability for systems with NVIDIA GPUs.

### Architecture Principles

1. **Cloud-Native**: Built for Kubernetes from the ground up
2. **Microservices**: Each component runs independently
3. **Declarative**: Configuration as code
4. **Scalable**: Horizontal and vertical scaling
5. **Resilient**: Self-healing and fault-tolerant
6. **Secure**: Defense in depth

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              ODIN Monitoring Stack                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   Grafana   │  │ Prometheus  │  │    Loki     │  │AlertManager │  │
│  │  (UI Layer) │  │  (Metrics)  │  │   (Logs)    │  │  (Alerts)   │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                 │                 │                 │         │
│  ┌──────┴─────────────────┴─────────────────┴─────────────────┴──────┐ │
│  │                        Service Mesh (Linkerd)                      │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────────┐  │
│  │    Node    │  │   NVIDIA   │  │  cAdvisor  │  │     Custom     │  │
│  │  Exporter  │  │   DCGM     │  │            │  │   Exporters    │  │
│  └────────────┘  └────────────┘  └────────────┘  └────────────────┘  │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                     Kubernetes Infrastructure                       │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐   │ │
│  │  │   Pods   │  │ Services │  │ Ingress  │  │ Persistent     │   │ │
│  │  │          │  │          │  │          │  │ Volumes        │   │ │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                          Host Infrastructure                        │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐   │ │
│  │  │   CPU    │  │  Memory  │  │   Disk   │  │  NVIDIA GPU    │   │ │
│  │  │          │  │          │  │          │  │  RTX Series    │   │ │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Prometheus (Metrics Collection)

**Purpose**: Time-series database for metrics collection and storage

**Architecture**:
```yaml
Prometheus Architecture:
├── Scrape Manager
│   ├── Service Discovery
│   ├── Target Management
│   └── Scrape Pools
├── TSDB (Time Series Database)
│   ├── Head Block (In-Memory)
│   ├── WAL (Write-Ahead Log)
│   └── Persistent Blocks
├── Query Engine
│   ├── PromQL Parser
│   ├── Query Executor
│   └── Result Formatter
└── Rule Manager
    ├── Recording Rules
    └── Alerting Rules
```

**Key Features**:
- Pull-based metric collection
- Multi-dimensional data model
- Powerful query language (PromQL)
- Built-in alerting
- Federation support

**Configuration**:
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'odin-prod'
    region: 'us-west'

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      # Dynamic service discovery configuration
```

### 2. Grafana (Visualization)

**Purpose**: Data visualization and dashboard platform

**Architecture**:
```yaml
Grafana Architecture:
├── Web Server
│   ├── HTTP API
│   ├── WebSocket Server
│   └── Static Assets
├── Backend Services
│   ├── Data Proxy
│   ├── Alert Engine
│   ├── Notification Engine
│   └── Plugin Manager
├── Data Sources
│   ├── Prometheus
│   ├── Loki
│   ├── Tempo
│   └── Custom Sources
└── Storage
    ├── Dashboard Store
    ├── User Store
    └── Alert Store
```

**Key Features**:
- Multi-datasource support
- Interactive dashboards
- Alerting and notifications
- User management
- Plugin ecosystem

### 3. Loki (Log Aggregation)

**Purpose**: Horizontally scalable log aggregation system

**Architecture**:
```yaml
Loki Architecture:
├── Distributor
│   ├── Rate Limiting
│   ├── Validation
│   └── Hashing
├── Ingester
│   ├── Chunks
│   ├── Index
│   └── WAL
├── Querier
│   ├── Query Frontend
│   ├── Query Scheduler
│   └── Cache
└── Storage
    ├── Object Store (S3/GCS/Filesystem)
    └── Index Store (BoltDB/DynamoDB)
```

**Key Features**:
- Label-based indexing
- LogQL query language
- Low resource usage
- Prometheus-like architecture

### 4. AlertManager (Alert Routing)

**Purpose**: Alert deduplication, grouping, and routing

**Architecture**:
```yaml
AlertManager Architecture:
├── API
│   ├── Alert Receiver
│   └── Configuration API
├── Dispatch
│   ├── Route Matching
│   ├── Grouping
│   └── Deduplication
├── Inhibition
│   └── Rule Engine
├── Silencing
│   └── Silence Store
└── Notification
    ├── Email
    ├── Webhook
    ├── PagerDuty
    └── Slack
```

**Routing Configuration**:
```yaml
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
    - match:
        alertname: GPUHighTemperature
      receiver: 'gpu-team'
```

## Data Flow Architecture

### Metrics Flow

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Exporters  │      │ Prometheus  │      │   Grafana   │
│             │◄─────│             │◄─────│             │
│ /metrics    │ Pull │   Storage   │Query │ Dashboards  │
└─────────────┘      └─────────────┘      └─────────────┘
                            │
                            ▼
                     ┌─────────────┐
                     │AlertManager │
                     │             │
                     │Notification │
                     └─────────────┘
```

### Logs Flow

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Nodes     │      │  Promtail   │      │    Loki     │
│             │─────►│             │─────►│             │
│ Log Files   │ Tail │   Parser    │ Push │   Storage   │
└─────────────┘      └─────────────┘      └─────────────┘
                                                  │
                                                  ▼
                                           ┌─────────────┐
                                           │   Grafana   │
                                           │             │
                                           │ Log Viewer  │
                                           └─────────────┘
```

### Traces Flow

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│Applications │      │ OTel Agent  │      │    Tempo    │
│             │─────►│             │─────►│             │
│   Traces    │ OTLP │  Processor  │ OTLP │   Storage   │
└─────────────┘      └─────────────┘      └─────────────┘
                                                  │
                                                  ▼
                                           ┌─────────────┐
                                           │   Grafana   │
                                           │             │
                                           │Trace Viewer │
                                           └─────────────┘
```

## Network Architecture

### Service Communication

```yaml
Network Topology:
├── Cluster Network (10.0.0.0/16)
│   ├── Monitoring Namespace (10.0.1.0/24)
│   │   ├── Prometheus: 10.0.1.10:9090
│   │   ├── Grafana: 10.0.1.20:3000
│   │   ├── Loki: 10.0.1.30:3100
│   │   └── AlertManager: 10.0.1.40:9093
│   └── Service Mesh Control Plane (10.0.2.0/24)
│       └── Linkerd: 10.0.2.10:8086
├── External Access
│   ├── Ingress Controller
│   │   ├── grafana.example.com → Grafana
│   │   └── prometheus.example.com → Prometheus
│   └── NodePort Services
│       └── Grafana: NodePort 30300
└── Inter-Service Communication
    ├── mTLS (via Linkerd)
    └── Service Discovery (CoreDNS)
```

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-network-policy
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    - podSelector: {}
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 3000  # Grafana
    - protocol: TCP
      port: 9090  # Prometheus
  egress:
  - to:
    - namespaceSelector: {}  # Allow all namespaces for scraping
  - to:
    - podSelector: {}
  - ports:
    - protocol: TCP
      port: 53  # DNS
    - protocol: UDP
      port: 53  # DNS
```

## Storage Architecture

### Storage Classes

```yaml
Storage Hierarchy:
├── Fast Storage (SSD)
│   ├── Prometheus TSDB
│   ├── Loki Index
│   └── Grafana Database
├── Bulk Storage (HDD)
│   ├── Loki Chunks
│   ├── Prometheus Snapshots
│   └── Backup Storage
└── Object Storage (S3/MinIO)
    ├── Long-term Metrics (Thanos)
    ├── Archive Logs
    └── Trace Storage
```

### Persistent Volume Configuration

```yaml
# Prometheus Storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: fast-ssd
  
# Retention Policies
Prometheus: 30 days local, 1 year in object storage
Loki: 7 days local, 90 days in object storage
Grafana: Indefinite (dashboards/configs)
```

### Backup Architecture

```
┌─────────────────────────────────────────────────────┐
│                 Backup Strategy                      │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────┐         ┌─────────────────────┐  │
│  │   CronJob   │────────►│   Backup Script     │  │
│  │  (Daily)    │         │ - Prometheus Data   │  │
│  └─────────────┘         │ - Grafana Configs   │  │
│                          │ - Loki Data         │  │
│                          └──────────┬───────────┘  │
│                                     │               │
│                          ┌──────────▼───────────┐  │
│                          │   Local Backup       │  │
│                          │   - 7 day retention  │  │
│                          └──────────┬───────────┘  │
│                                     │               │
│                          ┌──────────▼───────────┐  │
│                          │   Remote Backup      │  │
│                          │   - S3/GCS          │  │
│                          │   - 90 day retention │  │
│                          └──────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Security Architecture

### Defense in Depth

```yaml
Security Layers:
├── Network Security
│   ├── Network Policies
│   ├── Service Mesh (mTLS)
│   └── Ingress TLS
├── Authentication
│   ├── OAuth2 Proxy
│   ├── Grafana Auth
│   └── API Keys
├── Authorization
│   ├── RBAC
│   ├── Service Accounts
│   └── Pod Security Policies
├── Data Security
│   ├── Encryption at Rest
│   ├── Encryption in Transit
│   └── Secret Management
└── Audit & Compliance
    ├── Audit Logging
    ├── Access Logs
    └── Compliance Reports
```

### Authentication Flow

```
┌─────────┐      ┌─────────────┐      ┌─────────────┐      ┌──────────┐
│  User   │─────►│OAuth2 Proxy │─────►│   Grafana   │─────►│Dashboard │
│         │      │   (GitHub)  │      │    Auth     │      │          │
└─────────┘      └─────────────┘      └─────────────┘      └──────────┘
     │                                        │
     │                                        ▼
     │                                 ┌─────────────┐
     └────────────────────────────────►│ Prometheus  │
              Direct API Access         │  (Token)    │
              (with API Token)          └─────────────┘
```

### RBAC Configuration

```yaml
# Monitoring Admin Role
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-admin
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/metrics", "services", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets"]
  verbs: ["get", "list", "watch", "update", "patch"]
---
# Read-only User Role
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-viewer
rules:
- apiGroups: [""]
  resources: ["nodes", "services", "pods"]
  verbs: ["get", "list"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
```

## High Availability Design

### HA Component Architecture

```yaml
HA Configuration:
├── Prometheus HA
│   ├── Primary-Secondary with Thanos
│   ├── Cross-region federation
│   └── Deduplication via external labels
├── Grafana HA
│   ├── Multiple replicas
│   ├── Shared database backend
│   └── Session affinity
├── Loki HA
│   ├── Distributor replicas
│   ├── Ingester replication factor: 3
│   └── Querier with caching
└── AlertManager HA
    ├── Gossip protocol clustering
    ├── Notification deduplication
    └── State replication
```

### Failover Scenarios

```
Normal Operation:
┌─────────┐     ┌─────────┐     ┌─────────┐
│ Prom-1  │     │ Prom-2  │     │ Thanos  │
│ Active  │────►│ Standby │────►│ Query   │
└─────────┘     └─────────┘     └─────────┘

Failover:
┌─────────┐     ┌─────────┐     ┌─────────┐
│ Prom-1  │     │ Prom-2  │     │ Thanos  │
│  Down   │  X  │ Active  │────►│ Query   │
└─────────┘     └─────────┘     └─────────┘
```

## GPU Monitoring Architecture

### NVIDIA Integration

```yaml
GPU Monitoring Stack:
├── NVIDIA Drivers
│   └── nvidia-smi interface
├── NVIDIA Container Runtime
│   └── GPU device exposure
├── Kubernetes Device Plugin
│   ├── GPU discovery
│   └── Resource allocation
├── DCGM (Data Center GPU Manager)
│   ├── Health monitoring
│   ├── Diagnostics
│   └── Metrics collection
└── DCGM Exporter
    ├── Prometheus metrics
    ├── GPU telemetry
    └── Custom labels
```

### GPU Metrics Collection

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│  NVIDIA GPU     │────►│ DCGM Daemon  │────►│   DCGM      │
│  Hardware       │     │              │     │  Exporter   │
│  - Temperature  │     │ Collects all │     │             │
│  - Utilization  │     │ GPU metrics  │     │ /metrics    │
│  - Memory       │     │              │     │  endpoint   │
│  - Power        │     └──────────────┘     └─────────────┘
└─────────────────┘                                 │
                                                    ▼
                                            ┌─────────────┐
                                            │ Prometheus  │
                                            │             │
                                            │  Scrapes    │
                                            │  metrics    │
                                            └─────────────┘
```

### GPU Resource Management

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  containers:
  - name: cuda-app
    image: nvidia/cuda:11.8.0
    resources:
      limits:
        nvidia.com/gpu: 1  # Request 1 GPU
    env:
    - name: NVIDIA_VISIBLE_DEVICES
      value: "0"  # Use GPU 0
    - name: NVIDIA_DRIVER_CAPABILITIES
      value: "compute,utility"
```

## Service Mesh Integration

### Linkerd Architecture

```yaml
Service Mesh Components:
├── Control Plane
│   ├── Controller
│   ├── Destination Service
│   ├── Identity Service
│   └── Web UI
├── Data Plane
│   ├── Proxy (per pod)
│   ├── mTLS
│   └── Telemetry
└── Observability
    ├── Metrics (Prometheus)
    ├── Traces (OpenTelemetry)
    └── Tap (Live traffic)
```

### Traffic Flow with Service Mesh

```
Without Service Mesh:
┌─────────┐         ┌─────────┐
│  Pod A  │────────►│  Pod B  │
└─────────┘         └─────────┘

With Service Mesh:
┌─────────┐      ┌─────────┐      ┌─────────┐      ┌─────────┐
│  Pod A  │─────►│ Proxy A │─────►│ Proxy B │─────►│  Pod B  │
└─────────┘      └─────────┘      └─────────┘      └─────────┘
                      │                  │
                      └──────mTLS────────┘
```

## Deployment Patterns

### GitOps Deployment

```yaml
GitOps Flow:
├── Git Repository
│   ├── k8s/base/        # Base configurations
│   ├── k8s/overlays/    # Environment overlays
│   └── .github/workflows # CI/CD pipelines
├── CI/CD Pipeline
│   ├── Validate manifests
│   ├── Run tests
│   └── Update image tags
└── ArgoCD (Future)
    ├── Sync with Git
    ├── Apply to cluster
    └── Monitor drift
```

### Progressive Deployment

```yaml
Deployment Strategy:
├── Phase 1: Foundation
│   ├── Namespace
│   ├── RBAC
│   └── Storage
├── Phase 2: Core Services
│   ├── Prometheus
│   ├── Grafana
│   └── Exporters
├── Phase 3: Logging
│   ├── Loki
│   ├── Promtail
│   └── Log dashboards
├── Phase 4: Advanced
│   ├── Service mesh
│   ├── Tracing
│   └── Custom exporters
└── Phase 5: Production
    ├── HA configuration
    ├── Security hardening
    └── Performance tuning
```

## Scaling Strategies

### Horizontal Scaling

```yaml
Horizontal Scaling Options:
├── Prometheus
│   ├── Sharding by job/namespace
│   ├── Federation for aggregation
│   └── Remote write for distribution
├── Grafana
│   ├── Multiple replicas
│   ├── Load balancer distribution
│   └── Caching layer (Redis)
├── Loki
│   ├── Microservices mode
│   ├── Separate read/write paths
│   └── Index/chunk separation
└── Exporters
    ├── DaemonSet for node metrics
    ├── Sidecar for pod metrics
    └── Standalone for services
```

### Vertical Scaling

```yaml
Resource Recommendations:
├── Small (Dev/Test)
│   ├── Prometheus: 2 CPU, 4GB RAM
│   ├── Grafana: 1 CPU, 2GB RAM
│   └── Loki: 1 CPU, 2GB RAM
├── Medium (Production)
│   ├── Prometheus: 4 CPU, 16GB RAM
│   ├── Grafana: 2 CPU, 4GB RAM
│   └── Loki: 2 CPU, 8GB RAM
└── Large (Enterprise)
    ├── Prometheus: 8 CPU, 32GB RAM
    ├── Grafana: 4 CPU, 8GB RAM
    └── Loki: 4 CPU, 16GB RAM
```

## Disaster Recovery

### DR Strategy

```yaml
Disaster Recovery Plan:
├── Backup Strategy
│   ├── Automated daily backups
│   ├── Offsite replication
│   └── Point-in-time recovery
├── RTO/RPO Targets
│   ├── RTO: 1 hour
│   ├── RPO: 15 minutes
│   └── Data retention: 90 days
├── Failover Procedures
│   ├── DNS failover
│   ├── Data restoration
│   └── Service validation
└── Testing
    ├── Monthly DR drills
    ├── Backup verification
    └── Runbook updates
```

### Recovery Procedures

```bash
# 1. Assess damage
kubectl get all -n monitoring

# 2. Restore from backup
./scripts/restore-monitoring.sh ~/odin-backups/latest

# 3. Verify services
kubectl wait --for=condition=ready pods --all -n monitoring

# 4. Validate data integrity
curl http://prometheus:9090/api/v1/query?query=up

# 5. Update DNS/routing
kubectl patch ingress monitoring-ingress -p '{"spec":{"rules":[...]}}'
```

## Performance Considerations

### Query Optimization

```yaml
Performance Best Practices:
├── Recording Rules
│   ├── Pre-calculate expensive queries
│   ├── Reduce query time
│   └── Lower resource usage
├── Retention Policies
│   ├── Local: High precision, short term
│   ├── Downsampled: Medium precision, medium term
│   └── Archived: Low precision, long term
├── Caching
│   ├── Query result cache
│   ├── Dashboard cache
│   └── API response cache
└── Resource Limits
    ├── Query timeout: 2 minutes
    ├── Max samples: 50 million
    └── Concurrent queries: 20
```

### Monitoring the Monitors

```promql
# Prometheus performance
rate(prometheus_engine_query_duration_seconds_sum[5m]) / 
rate(prometheus_engine_query_duration_seconds_count[5m])

# Grafana performance
histogram_quantile(0.99, rate(grafana_http_request_duration_seconds_bucket[5m]))

# Loki performance
histogram_quantile(0.99, rate(loki_request_duration_seconds_bucket{route="/loki/api/v1/query_range"}[5m]))
```

## Architecture Decision Records (ADRs)

### ADR-001: Kubernetes as Orchestration Platform
- **Status**: Accepted
- **Context**: Need container orchestration with GPU support
- **Decision**: Use Kubernetes (K3s for dev)
- **Consequences**: Learning curve, but industry standard

### ADR-002: Prometheus for Metrics
- **Status**: Accepted
- **Context**: Need reliable metrics collection
- **Decision**: Use Prometheus with Thanos for long-term storage
- **Consequences**: Pull-based model, powerful but resource intensive

### ADR-003: Linkerd for Service Mesh
- **Status**: Accepted
- **Context**: Need mTLS and observability
- **Decision**: Use Linkerd over Istio
- **Consequences**: Simpler, less features than Istio

### ADR-004: GPU Monitoring via DCGM
- **Status**: Accepted
- **Context**: Need comprehensive GPU metrics
- **Decision**: Use NVIDIA DCGM with official exporter
- **Consequences**: Vendor lock-in, but best support

## Future Architecture Considerations

### Roadmap

```yaml
Future Enhancements:
├── Multi-Cluster Support
│   ├── Cluster federation
│   ├── Cross-cluster queries
│   └── Global dashboards
├── ML Integration
│   ├── Anomaly detection
│   ├── Predictive alerts
│   └── Capacity planning
├── Extended Observability
│   ├── Continuous profiling
│   ├── eBPF integration
│   └── Application insights
└── Cloud Native Evolution
    ├── Operator pattern
    ├── Multi-cloud support
    └── Edge deployments
```

## Conclusion

The ODIN architecture provides a robust, scalable, and secure monitoring platform optimized for GPU-accelerated workloads. By leveraging cloud-native patterns and industry-standard tools, it delivers comprehensive observability while maintaining operational simplicity.

Key architectural benefits:
- **Modularity**: Each component can be scaled independently
- **Resilience**: Self-healing with automatic recovery
- **Security**: Defense in depth with multiple layers
- **Performance**: Optimized for high-throughput metrics
- **Flexibility**: Extensible through standard interfaces

This architecture serves as the foundation for modern infrastructure monitoring, with particular emphasis on GPU workload observability and Kubernetes-native operations.