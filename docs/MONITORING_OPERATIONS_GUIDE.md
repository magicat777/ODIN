# ODIN Monitoring Stack Operations Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Daily Operations](#daily-operations)
4. [Accessing Services](#accessing-services)
5. [Common Tasks](#common-tasks)
6. [Troubleshooting](#troubleshooting)
7. [Maintenance](#maintenance)
8. [Performance Tuning](#performance-tuning)

## Overview

The ODIN (Observability Dashboard for Infrastructure and NVIDIA) monitoring stack provides comprehensive monitoring for your Razer Blade 18 running Ubuntu 22.04. It includes:

- **Metrics Collection**: Prometheus with various exporters
- **Visualization**: Grafana with custom dashboards
- **Log Aggregation**: Loki with Promtail
- **Alerting**: AlertManager with custom rules
- **Specialized Monitoring**: GPU, Razer hardware, power consumption, process analysis

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Grafana UI                           │
│  (Dashboards, Visualizations, Alerts)                       │
└────────────────┬───────────────────────────┬────────────────┘
                 │                           │
┌────────────────▼──────────┐   ┌───────────▼────────────────┐
│       Prometheus          │   │          Loki              │
│  (Metrics Time-Series)    │   │    (Log Aggregation)       │
└────────────────┬──────────┘   └───────────┬────────────────┘
                 │                           │
┌────────────────┴───────────────────────────┴────────────────┐
│                        Exporters                             │
├──────────────┬──────────────┬──────────────┬───────────────┤
│Node Exporter │Process Export│Power Exporter│Razer Exporter │
│              │              │              │               │
│System Metrics│Host Processes│RAPL/Battery  │OpenRazer API  │
└──────────────┴──────────────┴──────────────┴───────────────┘
```

### Data Flow
1. Exporters collect metrics from various sources
2. Prometheus scrapes metrics every 15 seconds
3. Grafana queries Prometheus and Loki for visualization
4. AlertManager processes alerts based on rules

## Daily Operations

### Health Check Routine

1. **Check Component Status**
   ```bash
   kubectl get pods -n monitoring
   kubectl get pvc -n monitoring
   ```

2. **Verify Metrics Collection**
   ```bash
   # Check Prometheus targets
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Open http://localhost:9090/targets
   ```

3. **Review Alerts**
   ```bash
   kubectl port-forward -n monitoring svc/alertmanager 9093:9093
   # Open http://localhost:9093/#/alerts
   ```

### Monitoring Key Metrics

- **CPU Usage**: Should stay below 80% sustained
- **Memory Usage**: Alert at 85% utilization
- **GPU Temperature**: Warning at 80°C, critical at 90°C
- **Power Consumption**: Monitor against baseline profiles
- **Process Count**: Alert if >1000 processes
- **Zombie Processes**: Critical if >5 zombies

## Accessing Services

### Port Forwarding

```bash
# Grafana (default user: admin, password: admin)
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# AlertManager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093

# Loki (API only, use Grafana for queries)
kubectl port-forward -n monitoring svc/loki 3100:3100
```

### Direct NodePort Access

```bash
# Get Grafana NodePort
kubectl get svc grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}'
# Access at http://<node-ip>:<nodeport>
```

## Common Tasks

### Adding New Dashboards

1. Create dashboard in Grafana UI
2. Export as JSON
3. Create ConfigMap:
   ```bash
   kubectl create configmap my-dashboard \
     --from-file=dashboard.json \
     -n monitoring
   ```
4. Mount in Grafana deployment

### Creating Custom Alerts

1. Edit Prometheus config:
   ```bash
   kubectl edit configmap prometheus-config -n monitoring
   ```

2. Add alert rule:
   ```yaml
   - alert: MyCustomAlert
     expr: my_metric > threshold
     for: 5m
     labels:
       severity: warning
     annotations:
       summary: "Custom alert triggered"
   ```

3. Restart Prometheus:
   ```bash
   kubectl rollout restart deployment/prometheus -n monitoring
   ```

### Querying Logs

1. Access Grafana
2. Go to Explore → Loki
3. Use LogQL queries:
   ```
   {job="systemd-journal"} |= "error"
   {job="systemd-journal"} |~ "kernel|hardware"
   ```

### Manual Backup

```bash
kubectl apply -f /home/magicat777/projects/ODIN/k8s/manual-backup-job.yaml
kubectl logs -f -n monitoring -l job-name=monitoring-backup-manual
```

## Troubleshooting

### Pod Issues

**Pod CrashLoopBackOff**
```bash
# Check logs
kubectl logs -n monitoring <pod-name> --previous

# Describe pod
kubectl describe pod -n monitoring <pod-name>

# Common fixes:
# - Check resource limits
# - Verify volume mounts
# - Check image availability
```

**Pod Pending**
```bash
# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Common causes:
# - Insufficient resources
# - PVC not bound
# - Node selector mismatch
```

### Metrics Missing

1. **Check Exporter Status**
   ```bash
   kubectl get pods -n monitoring | grep exporter
   ```

2. **Verify Prometheus Scraping**
   ```bash
   # Check Prometheus targets
   curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'
   ```

3. **Test Exporter Directly**
   ```bash
   kubectl exec -n monitoring <exporter-pod> -- curl localhost:<port>/metrics
   ```

### High Resource Usage

1. **Identify Resource Consumers**
   ```bash
   kubectl top pods -n monitoring
   ```

2. **Check Prometheus Retention**
   ```bash
   # Reduce retention if disk full
   kubectl edit deployment prometheus -n monitoring
   # Add: --storage.tsdb.retention.time=7d
   ```

3. **Optimize Queries**
   - Use recording rules for complex queries
   - Increase scrape intervals for non-critical metrics

### Dashboard Not Loading

1. **Check ConfigMap**
   ```bash
   kubectl get configmap -n monitoring | grep dashboard
   ```

2. **Verify Mount**
   ```bash
   kubectl describe deployment grafana -n monitoring | grep -A5 Mounts
   ```

3. **Check Grafana Logs**
   ```bash
   kubectl logs -n monitoring deployment/grafana | grep -i error
   ```

## Maintenance

### Weekly Tasks

1. **Review Backup Status**
   ```bash
   kubectl get cronjobs -n monitoring
   ls -la /var/lib/odin/backups/configs/
   ```

2. **Check Storage Usage**
   ```bash
   df -h /var/lib/odin/
   kubectl exec -n monitoring prometheus-0 -- df -h /prometheus
   ```

3. **Update Exporters**
   ```bash
   # Check for updates
   kubectl get daemonsets -n monitoring -o wide
   ```

### Monthly Tasks

1. **Test Backup Restore**
   - Create test namespace
   - Perform restore
   - Verify data integrity

2. **Review Alert Rules**
   - Check for false positives
   - Adjust thresholds based on baselines

3. **Performance Analysis**
   - Review baseline profiles
   - Update thresholds if needed

### Upgrade Procedures

1. **Backup First**
   ```bash
   kubectl apply -f /home/magicat777/projects/ODIN/k8s/manual-backup-job.yaml
   ```

2. **Update Images**
   ```bash
   kubectl set image deployment/grafana grafana=grafana/grafana:NEW_VERSION -n monitoring
   ```

3. **Verify Functionality**
   - Check all dashboards load
   - Verify metrics collection
   - Test alerting

## Performance Tuning

### Prometheus Optimization

1. **Adjust Scrape Intervals**
   ```yaml
   global:
     scrape_interval: 30s  # Increase for less critical metrics
   ```

2. **Use Recording Rules**
   ```yaml
   groups:
   - name: aggregations
     rules:
     - record: instance:node_cpu:rate5m
       expr: rate(node_cpu_seconds_total[5m])
   ```

3. **Optimize Storage**
   ```bash
   # Enable compression
   --storage.tsdb.compress
   ```

### Grafana Optimization

1. **Dashboard Best Practices**
   - Limit time ranges
   - Use variables for repeated queries
   - Enable caching

2. **Query Optimization**
   - Use `rate()` instead of `irate()` for smoother graphs
   - Aggregate before graphing
   - Limit cardinality

### Resource Limits

Adjust based on your needs:
```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

## Advanced Topics

### Custom Exporters

Template for creating custom exporters:
```python
from prometheus_client import start_http_server, Gauge
import time

my_metric = Gauge('my_custom_metric', 'Description')

def collect_metrics():
    my_metric.set(42)

if __name__ == '__main__':
    start_http_server(9999)
    while True:
        collect_metrics()
        time.sleep(30)
```

### Integration with External Systems

1. **Remote Write**
   ```yaml
   remote_write:
   - url: "https://prometheus-remote.example.com/write"
   ```

2. **Federation**
   ```yaml
   - job_name: 'federate'
     honor_labels: true
     metrics_path: '/federate'
     params:
       'match[]':
       - '{job="prometheus"}'
   ```

### Security Hardening

1. **Enable Authentication**
   - Configure Grafana LDAP/OAuth
   - Add basic auth to Prometheus

2. **Network Policies**
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: monitoring-network-policy
   spec:
     podSelector:
       matchLabels:
         app: prometheus
   ```

3. **RBAC Restrictions**
   - Limit service account permissions
   - Use separate namespaces for sensitive data

## Support and References

- **Prometheus Documentation**: https://prometheus.io/docs/
- **Grafana Documentation**: https://grafana.com/docs/
- **Loki Documentation**: https://grafana.com/docs/loki/
- **Project Issues**: /home/magicat777/projects/ODIN/issues/

For specific issues, check:
1. Component logs
2. Kubernetes events
3. Prometheus targets page
4. Grafana datasource configuration